#!/usr/bin/env python3
"""End-to-end SIH flight test (MAVSDK, host side).

Connects to a running PX4 (Linux SITL or QNX VM), arms, takes off to 10 m,
holds 10 s, flies a 4-waypoint square mission, lands and disarms.

Asserts:
  * altitude stays within +/-1 m of the target during the hold
  * mission reports finished
  * vehicle reaches landed state and disarms

Usage: test_flight.py [--url udpin://0.0.0.0:14540] [--alt 10] [--timeout 300]
Needs mavsdk-grpc (pip install mavsdk-grpc).
"""

import argparse
import asyncio
import math
import sys

from mavsdk_grpc import System
from mavsdk_grpc.mission import MissionItem, MissionPlan
from mavsdk_grpc.telemetry import FlightMode, LandedState


# EKF height in SIH overshoots for ~15 s after takeoff; measure the hold after it settles.
SETTLE_S = 20.0


def log(msg):
    print(f"[test_flight] {msg}", flush=True)


def offset(lat, lon, north_m, east_m):
    """Shift a lat/lon by metres (flat-earth, fine for <1 km)."""
    dlat = north_m / 6378137.0
    dlon = east_m / (6378137.0 * math.cos(math.radians(lat)))
    return lat + math.degrees(dlat), lon + math.degrees(dlon)


def make_item(lat, lon, alt):
    return MissionItem(
        lat,
        lon,
        alt,
        5.0,
        True,
        float("nan"),
        float("nan"),
        MissionItem.CameraAction.NONE,
        float("nan"),
        float("nan"),
        float("nan"),
        float("nan"),
        float("nan"),
        MissionItem.VehicleAction.NONE,
    )


async def wait_for(gen, pred, timeout, what):
    async def inner():
        async for v in gen:
            if pred(v):
                return v

    try:
        return await asyncio.wait_for(inner(), timeout)
    except asyncio.TimeoutError:
        raise AssertionError(f"timeout waiting for {what}")


async def run(url, alt, timeout):
    drone = System()
    await drone.connect(system_address=url)

    log(f"connecting on {url}")
    await wait_for(
        drone.core.connection_state(), lambda s: s.is_connected, 60, "connection"
    )
    log("connected")

    await wait_for(
        drone.telemetry.health(),
        lambda h: (
            h.is_global_position_ok and h.is_home_position_ok and h.is_local_position_ok
        ),
        120,
        "health ok (global/home/local position)",
    )
    log("health ok")

    home = await wait_for(
        drone.telemetry.home(), lambda h: not math.isnan(h.latitude_deg), 30, "home"
    )
    log(f"home {home.latitude_deg:.6f},{home.longitude_deg:.6f}")

    ground = await wait_for(
        drone.telemetry.position_velocity_ned(), lambda p: True, 10, "local position"
    )
    ground_up = -ground.position.down_m
    log(f"ground height in local frame {ground_up:.2f} m")

    await drone.action.set_takeoff_altitude(alt)
    await drone.action.arm()
    log("armed")
    await drone.action.takeoff()

    await wait_for(
        drone.telemetry.position(),
        lambda p: p.relative_altitude_m > alt - 0.5,
        60,
        f"reach {alt} m",
    )
    # Takeoff is done when PX4 switches to HOLD; then wait for vertical speed to settle.
    await wait_for(
        drone.telemetry.flight_mode(),
        lambda m: m == FlightMode.HOLD,
        60,
        "HOLD after takeoff",
    )
    await wait_for(
        drone.telemetry.velocity_ned(),
        lambda v: abs(v.down_m_s) < 0.1,
        30,
        "vertical speed < 0.1 m/s",
    )
    log(f"takeoff complete, settling {SETTLE_S:.0f} s")
    await asyncio.sleep(SETTLE_S)

    # Hold 10 s, sample height from PX4's local position estimate (EKF2, NED).
    # The global relative_altitude_m mixes in GPS altitude noise and is not
    # what the position controller tracks.
    samples = []

    async def sample():
        async for p in drone.telemetry.position_velocity_ned():
            samples.append(-p.position.down_m - ground_up)

    await drone.telemetry.set_rate_position_velocity_ned(20.0)
    task = asyncio.create_task(sample())
    await asyncio.sleep(10)
    task.cancel()
    if not samples:
        raise AssertionError("no local position samples during the hold")
    lo, hi = min(samples), max(samples)
    log(f"hold: {len(samples)} samples, alt min {lo:.2f} max {hi:.2f}")
    assert len(samples) > 10, "too few altitude samples during hold"
    assert lo >= alt - 1.0 and hi <= alt + 1.0, (
        f"hold altitude out of +/-1 m: {lo:.2f}..{hi:.2f}"
    )

    # 4-waypoint square, 20 m side, starting north of home.
    side = 20.0
    corners = [(side, 0), (side, side), (0, side), (0, 0)]
    items = [
        make_item(*offset(home.latitude_deg, home.longitude_deg, n, e), alt)
        for n, e in corners
    ]
    await drone.mission.set_return_to_launch_after_mission(False)
    await drone.mission.upload_mission(MissionPlan(items))
    log("mission uploaded")

    # Commander can refuse MISSION for a moment right after upload, until the
    # navigator has validated the new mission. Retry until the mode changes.
    for attempt in range(10):
        await asyncio.sleep(1)
        await drone.mission.start_mission()
        try:
            await wait_for(drone.telemetry.flight_mode(),
                           lambda m: m == FlightMode.MISSION, 3, "MISSION mode")
            break
        except AssertionError:
            log(f"  MISSION mode not entered (attempt {attempt + 1}), retrying")
    else:
        raise AssertionError("vehicle never entered MISSION mode")
    log("mission started")

    def progress(m):
        log(f"  mission {m.current}/{m.total}")
        return m.total > 0 and m.current == m.total

    await wait_for(
        drone.mission.mission_progress(),
        progress,
        timeout,
        "mission finished",
    )
    assert await drone.mission.is_mission_finished(), "mission not finished"
    log("mission finished")

    await drone.action.land()
    await wait_for(
        drone.telemetry.landed_state(),
        lambda s: s == LandedState.ON_GROUND,
        90,
        "landed",
    )
    log("landed")
    await wait_for(drone.telemetry.armed(), lambda a: not a, 30, "disarm")
    log("disarmed")
    log("PASS")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="udpin://0.0.0.0:14540")
    ap.add_argument("--alt", type=float, default=10.0)
    ap.add_argument("--timeout", type=float, default=300.0)
    a = ap.parse_args()
    try:
        asyncio.run(run(a.url, a.alt, a.timeout))
    except AssertionError as e:
        log(f"FAIL: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
