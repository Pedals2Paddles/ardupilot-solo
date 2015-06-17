/// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: nil -*-

// Code to detect a crash main ArduCopter code
#define CRASH_CHECK_TRIGGER_SEC         2       // 2 seconds inverted indicates a crash
#define CRASH_CHECK_ANGLE_DEVIATION_CD  2000    // 20 degrees beyond angle max is signal we are inverted
#define CRASH_CHECK_ACCEL_MAX           3.0f    // vehicle must be accelerating less than 3m/s/s to be considered crashed

// crash_check - disarms motors if a crash has been detected
// crashes are detected by the vehicle being more than 20 degrees beyond it's angle limits continuously for more than 1 second
// called at MAIN_LOOP_RATE
void crash_check()
{
    static uint16_t crash_counter;  // number of iterations vehicle may have been crashed

    // return immediately if disarmed
    if (!motors.armed() || ap.land_complete) {
        crash_counter = 0;
        return;
    }

    // return immediately if we are not in an angle stabilize flight mode or we are flipping
    if (control_mode == ACRO || control_mode == FLIP) {
        crash_counter = 0;
        return;
    }

    // vehicle not crashed if 1hz filtered acceleration is more than 3m/s (1G on Z-axis has been subtracted)
    if (land_accel_ef_filter.get().length() >= CRASH_CHECK_ACCEL_MAX) {
        crash_counter = 0;
        return;
    }

    // check for angle error over 30 degrees
    const Vector3f angle_error = attitude_control.angle_bf_error();
    if (pythagorous2(angle_error.x, angle_error.y) <= 3000.0f) {
        crash_counter = 0;
        return;
    }

    // we may be crashing
    crash_counter++;

    // check if crashing for 2 seconds
    if (crash_counter >= (CRASH_CHECK_TRIGGER_SEC * MAIN_LOOP_RATE)) {
        // log an error in the dataflash
        Log_Write_Error(ERROR_SUBSYSTEM_CRASH_CHECK, ERROR_CODE_CRASH_CHECK_CRASH);
        // send message to gcs
        gcs_send_text_P(SEVERITY_HIGH,PSTR("Crash: Disarming"));
        // disarm motors
        init_disarm_motors();
    }
}

#if PARACHUTE == ENABLED

// Code to detect a crash main ArduCopter code
#define PARACHUTE_CHECK_TRIGGER_SEC         1       // 1 second of loss of control triggers the parachute
#define PARACHUTE_CHECK_ANGLE_DEVIATION_CD  3000    // 30 degrees off from target indicates a loss of control

// parachute_check - disarms motors and triggers the parachute if serious loss of control has been detected
// vehicle is considered to have a "serious loss of control" by the vehicle being more than 30 degrees off from the target roll and pitch angles continuously for 1 second
// called at MAIN_LOOP_RATE
void parachute_check()
{
    static uint16_t control_loss_count;	// number of iterations we have been out of control
    static int32_t baro_alt_start;

    // exit immediately if parachute is not enabled
    if (!parachute.enabled()) {
        return;
    }

    // call update to give parachute a chance to move servo or relay back to off position
    parachute.update();

    // return immediately if motors are not armed or pilot's throttle is above zero
    if (!motors.armed()) {
        control_loss_count = 0;
        return;
    }

    // return immediately if we are not in an angle stabilize flight mode or we are flipping
    if (control_mode == ACRO || control_mode == FLIP) {
        control_loss_count = 0;
        return;
    }

    // ensure we are flying
    if (ap.land_complete) {
        control_loss_count = 0;
        return;
    }

    // ensure the first control_loss event is from above the min altitude
    if (control_loss_count == 0 && parachute.alt_min() != 0 && (baro_alt < (int32_t)parachute.alt_min() * 100)) {
        return;
    }

    // get desired lean angles
    const Vector3f& target_angle = attitude_control.angle_ef_targets();

    // check roll and pitch angles
    if (labs(ahrs.roll_sensor - target_angle.x) > CRASH_CHECK_ANGLE_DEVIATION_CD ||
        labs(ahrs.pitch_sensor - target_angle.y) > CRASH_CHECK_ANGLE_DEVIATION_CD) {
        control_loss_count++;

        // don't let control_loss_count get too high
        if (control_loss_count > (PARACHUTE_CHECK_TRIGGER_SEC*MAIN_LOOP_RATE)) {
            control_loss_count = (PARACHUTE_CHECK_TRIGGER_SEC*MAIN_LOOP_RATE);
        }

        // record baro alt if we have just started losing control
        if (control_loss_count == 1) {
            baro_alt_start = baro_alt;

        // exit if baro altitude change indicates we are not falling
        }else if (baro_alt >= baro_alt_start) {
            control_loss_count = 0;
            return;

        // To-Do: add check that the vehicle is actually falling

        // check if loss of control for at least 1 second
        }else if (control_loss_count >= (PARACHUTE_CHECK_TRIGGER_SEC*MAIN_LOOP_RATE)) {
            // reset control loss counter
            control_loss_count = 0;
            // log an error in the dataflash
            Log_Write_Error(ERROR_SUBSYSTEM_CRASH_CHECK, ERROR_CODE_CRASH_CHECK_LOSS_OF_CONTROL);
            // release parachute
            parachute_release();
        }
    }else{
        // we are not inverted so reset counter
        control_loss_count = 0;
    }
}

// parachute_release - trigger the release of the parachute, disarm the motors and notify the user
static void parachute_release()
{
    // send message to gcs and dataflash
    gcs_send_text_P(SEVERITY_HIGH,PSTR("Parachute: Released!"));
    Log_Write_Event(DATA_PARACHUTE_RELEASED);

    // disarm motors
    init_disarm_motors();

    // release parachute
    parachute.release();
}

// parachute_manual_release - trigger the release of the parachute, after performing some checks for pilot error
//   checks if the vehicle is landed 
static void parachute_manual_release()
{
    // exit immediately if parachute is not enabled
    if (!parachute.enabled()) {
        return;
    }

    // do not release if we are landed or below the minimum altitude above home
    if (ap.land_complete || (parachute.alt_min() != 0 && (baro_alt < (int32_t)parachute.alt_min() * 100))) {
        // warn user of reason for failure
        gcs_send_text_P(SEVERITY_HIGH,PSTR("Parachute: Too Low"));
        // log an error in the dataflash
        Log_Write_Error(ERROR_SUBSYSTEM_PARACHUTE, ERROR_CODE_PARACHUTE_TOO_LOW);
        return;
    }

    // if we get this far release parachute
    parachute_release();
}

#endif // PARACHUTE == ENABLED
