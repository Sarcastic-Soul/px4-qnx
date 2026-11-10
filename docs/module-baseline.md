# Module baseline: SIH quad on Linux SITL

Reference for what a working SIH quadcopter runs. Captured on PX4 `v1.17.0`, board `px4_sitl_default`, airframe `10040_sihsim_quadx`, Linux x86_64 host.

How it was captured:

```sh
cd work/PX4-Autopilot && make px4_sitl_default
cd build/px4_sitl_default/rootfs
PX4_SIM_MODEL=sihsim_quadx PX4_SIMULATOR=sihsim ../bin/px4 -d
# in another shell, for each module: ../bin/px4-<module> status
../bin/px4-work_queue status
```

Flight check: `tests/test_flight.py` (arm, takeoff 10 m, 10 s hold, 4-waypoint square, land) passed against this build.

## Modules running after boot

Required for SIH quad flight (the QNX board must have these):

| Module | Role |
|---|---|
| `simulator_sih` | built-in physics + simulated IMU, runs at 250 Hz (thread `sih`) |
| `sensor_baro_sim`, `sensor_gps_sim`, `sensor_mag_sim` | simulated baro, GPS, mag from SIH truth |
| `sensors` | sensor voting, `vehicle_imu`, `vehicle_angular_velocity`, `vehicle_air_data`, ... |
| `ekf2` | state estimator (work queue `wq:INS0`) |
| `commander` | arming, modes, failsafes |
| `navigator` | takeoff, mission, land, RTL |
| `dataman` | mission storage (file `./dataman`) |
| `flight_mode_manager` | setpoint generation |
| `mc_pos_control`, `mc_att_control`, `mc_rate_control` | multicopter control cascade |
| `control_allocator` | mixer |
| `pwm_out_sim` | actuator output back to SIH |
| `land_detector` | landed/takeoff detection |
| `mc_hover_thrust_estimator` | hover thrust for altitude control |
| `mavlink` | GCS/MAVSDK link (UDP 14550 GCS, 14540 offboard) |
| `logger` | ULog to `./log` |
| `battery_simulator`, `system_power_simulator` | fake battery/power so preflight checks pass |
| `manual_control`, `rc_update` | input handling (required by commander) |
| `load_mon` | CPU/RAM load reporting (needs a platform hook) |
| `param` (systemcmd) | parameter storage `parameters.bson` |

Started by the generic POSIX startup but not needed for SIH flight (drop or keep on QNX as convenient):

- `uxrce_dds_client` (ROS 2 bridge, no agent here)
- `gyro_fft`, `gyro_calibration`, `mc_autotune_attitude_control`, `payload_deliverer`, `tone_alarm`, `landing_target_estimator`

Shell commands used by the startup script / tests: `param`, `listener`, `uorb`, `work_queue`, `ver`, `perf`, `shutdown`.

## Threads (Linux `ps -L`)

```
px4 (main), hpwork, lpwork, wkr_hrt, wq:manager, wq:lp_default, wq:hp_default,
wq:rate_ctrl, wq:INS0, wq:nav_and_controllers, dataman, sih, commander, navigator,
uxrce_dds_clien, mavlink_if0..4, mavlink_rcv_if0..4, logger, log_writer_file
```

## Work queues (`work_queue status`)

```
wq:rate_ctrl            control_allocator, mc_rate_control, pwm_out_sim, vehicle_angular_velocity  @250 Hz
wq:nav_and_controllers  flight_mode_manager 50 Hz, land_detector, mc_att_control 250 Hz,
                        mc_hover_thrust_estimator, mc_pos_control, sensors 250 Hz,
                        vehicle_acceleration, vehicle_air_data, vehicle_gps_position, vehicle_magnetometer
wq:INS0                 ekf2 250 Hz, vehicle_imu 250 Hz
wq:hp_default           battery_simulator, gyro_fft, manual_control, rc_update, sensor_*_sim,
                        system_power_simulator, tone_alarm, mc_autotune_attitude_control
wq:lp_default           gyro_calibration, load_mon, parameters, payload_deliverer
```

Loop rates are the target numbers for QNX: rate controller and EKF at 250 Hz (4000 us interval).

## Notes from the baseline run

- The SITL startup script sets `SYS_AUTOSTART=10040` from `PX4_SIM_MODEL=sihsim_quadx`; parameters persist in `parameters.bson`.
- `MAVLink only on localhost` by default. On QNX the GCS is at `10.0.2.2` (QEMU user NAT), so the QNX startup must set the remote address or `MAV_x_BROADCAST`.
- Commander may refuse `MISSION` mode right after upload; `tests/test_flight.py` retries until the mode changes.
- `relative_altitude_m` (GPS based) shows +/-1.5 m noise in SIH; the hold check uses the EKF2 local position, which is what the position controller tracks (9.95 to 10.17 m in the baseline run).
