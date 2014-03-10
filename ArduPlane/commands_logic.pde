/// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: nil -*-

// forward declarations to make compiler happy
static void do_takeoff(const AP_Mission::Mission_Command& cmd);
static void do_nav_wp(const AP_Mission::Mission_Command& cmd);
static void do_land(const AP_Mission::Mission_Command& cmd);
static void do_loiter_unlimited(const AP_Mission::Mission_Command& cmd);
static void do_loiter_turns(const AP_Mission::Mission_Command& cmd);
static void do_loiter_time(const AP_Mission::Mission_Command& cmd);
static void do_wait_delay(const AP_Mission::Mission_Command& cmd);
static void do_within_distance(const AP_Mission::Mission_Command& cmd);
static void do_change_alt(const AP_Mission::Mission_Command& cmd);
static void do_change_speed(const AP_Mission::Mission_Command& cmd);
static void do_set_home(const AP_Mission::Mission_Command& cmd);
static AP_Mission::Mission_Command rally_find_best_cmd(const Location &myloc, const Location &homeloc);

/********************************************************************************/
// Command Event Handlers
/********************************************************************************/
static bool
start_command(const AP_Mission::Mission_Command& cmd)
{
    // log when new commands start
    if (g.log_bitmask & MASK_LOG_CMD) {
        Log_Write_Cmd(cmd);
    }

    // special handling for nav vs non-nav commands
    if (AP_Mission::is_nav_cmd(cmd)) {
    // set land_complete to false to stop us zeroing the throttle
    land_complete = false;

    // set takeoff_complete to true so we don't add extra evevator
        // except in a takeoff
    takeoff_complete = true;

        gcs_send_text_fmt(PSTR("Executing nav command ID #%i"),cmd.id);
    }else{
        gcs_send_text_fmt(PSTR("Executing command ID #%i"),cmd.id);
    }

    switch(cmd.id) {

    case MAV_CMD_NAV_TAKEOFF:
        do_takeoff(cmd);
        break;

    case MAV_CMD_NAV_WAYPOINT:                  // Navigate to Waypoint
        do_nav_wp(cmd);
        break;

    case MAV_CMD_NAV_LAND:              // LAND to Waypoint
        do_land(cmd);
        break;

    case MAV_CMD_NAV_LOITER_UNLIM:              // Loiter indefinitely
        do_loiter_unlimited(cmd);
        break;

    case MAV_CMD_NAV_LOITER_TURNS:              // Loiter N Times
        do_loiter_turns(cmd);
        break;

    case MAV_CMD_NAV_LOITER_TIME:
        do_loiter_time(cmd);
        break;

    case MAV_CMD_NAV_RETURN_TO_LAUNCH:
        set_mode(RTL);
        break;

    // Conditional commands

    case MAV_CMD_CONDITION_DELAY:
        do_wait_delay(cmd);
        break;

    case MAV_CMD_CONDITION_DISTANCE:
        do_within_distance(cmd);
        break;

    case MAV_CMD_CONDITION_CHANGE_ALT:
        do_change_alt(cmd);
        break;

    // Do commands

    case MAV_CMD_DO_CHANGE_SPEED:
        do_change_speed(cmd);
        break;

    case MAV_CMD_DO_SET_HOME:
        do_set_home(cmd);
        break;

    case MAV_CMD_DO_SET_SERVO:
        ServoRelayEvents.do_set_servo(cmd.p1, cmd.content.location.alt);
        break;

    case MAV_CMD_DO_SET_RELAY:
        ServoRelayEvents.do_set_relay(cmd.p1, cmd.content.location.alt);
        break;

    case MAV_CMD_DO_REPEAT_SERVO:
        ServoRelayEvents.do_repeat_servo(cmd.p1, cmd.content.location.alt,
                                         cmd.content.location.lat, cmd.content.location.lng);
        break;

    case MAV_CMD_DO_REPEAT_RELAY:
        ServoRelayEvents.do_repeat_relay(cmd.p1, cmd.content.location.alt,
                                         cmd.content.location.lat);
        break;

#if CAMERA == ENABLED
    case MAV_CMD_DO_CONTROL_VIDEO:                      // Control on-board camera capturing. |Camera ID (-1 for all)| Transmission: 0: disabled, 1: enabled compressed, 2: enabled raw| Transmission mode: 0: video stream, >0: single images every n seconds (decimal)| Recording: 0: disabled, 1: enabled compressed, 2: enabled raw| Empty| Empty| Empty|
        break;

    case MAV_CMD_DO_DIGICAM_CONFIGURE:                  // Mission command to configure an on-board camera controller system. |Modes: P, TV, AV, M, Etc| Shutter speed: Divisor number for one second| Aperture: F stop number| ISO number e.g. 80, 100, 200, Etc| Exposure type enumerator| Command Identity| Main engine cut-off time before camera trigger in seconds/10 (0 means no cut-off)|
        break;

    case MAV_CMD_DO_DIGICAM_CONTROL:                    // Mission command to control an on-board camera controller system. |Session control e.g. show/hide lens| Zoom's absolute position| Zooming step value to offset zoom from the current position| Focus Locking, Unlocking or Re-locking| Shooting Command| Command Identity| Empty|
        do_take_picture();
        break;

    case MAV_CMD_DO_SET_CAM_TRIGG_DIST:
        camera.set_trigger_distance(cmd.content.location.alt);
        break;
#endif

#if MOUNT == ENABLED
    // Sets the region of interest (ROI) for a sensor set or the
    // vehicle itself. This can then be used by the vehicles control
    // system to control the vehicle attitude and the attitude of various
    // devices such as cameras.
    //    |Region of interest mode. (see MAV_ROI enum)| Waypoint index/ target ID. (see MAV_ROI enum)| ROI index (allows a vehicle to manage multiple cameras etc.)| Empty| x the location of the fixed ROI (see MAV_FRAME)| y| z|
    case MAV_CMD_NAV_ROI:
 #if 0
        // send the command to the camera mount
        camera_mount.set_roi_cmd(cmd);
 #else
        gcs_send_text_P(SEVERITY_LOW, PSTR("DO_SET_ROI not supported"));
 #endif
        break;

    case MAV_CMD_DO_MOUNT_CONFIGURE:                    // Mission command to configure a camera mount |Mount operation mode (see MAV_CONFIGURE_MOUNT_MODE enum)| stabilize roll? (1 = yes, 0 = no)| stabilize pitch? (1 = yes, 0 = no)| stabilize yaw? (1 = yes, 0 = no)| Empty| Empty| Empty|
        camera_mount.configure_cmd();
        break;

    case MAV_CMD_DO_MOUNT_CONTROL:                      // Mission command to control a camera mount |pitch(deg*100) or lat, depending on mount mode.| roll(deg*100) or lon depending on mount mode| yaw(deg*100) or alt (in cm) depending on mount mode| Empty| Empty| Empty| Empty|
        camera_mount.control_cmd();
        break;
#endif
    }

    return true;
}

static void exit_mission()
{
    gcs_send_text_fmt(PSTR("Returning to Home"));
    next_nav_command = rally_find_best_cmd(current_loc, home);
    next_nav_command.id = MAV_CMD_NAV_LOITER_UNLIM;
    start_command(next_nav_command);
}

/*******************************************************************************
Verify command Handlers

Each type of mission element has a "verify" operation. The verify
operation returns true when the mission element has completed and we
should move onto the next mission element.
*******************************************************************************/

static bool verify_command(const AP_Mission::Mission_Command& cmd)        // Returns true if command complete
{
    switch(cmd.id) {

    case MAV_CMD_NAV_TAKEOFF:
        return verify_takeoff();

    case MAV_CMD_NAV_LAND:
        return verify_land();

    case MAV_CMD_NAV_WAYPOINT:
        return verify_nav_wp();

    case MAV_CMD_NAV_LOITER_UNLIM:
        return verify_loiter_unlim();

    case MAV_CMD_NAV_LOITER_TURNS:
        return verify_loiter_turns();

    case MAV_CMD_NAV_LOITER_TIME:
        return verify_loiter_time();

    case MAV_CMD_NAV_RETURN_TO_LAUNCH:
        return verify_RTL();

    // Conditional commands

    case MAV_CMD_CONDITION_DELAY:
        return verify_wait_delay();
        break;

    case MAV_CMD_CONDITION_DISTANCE:
        return verify_within_distance();
        break;

    case MAV_CMD_CONDITION_CHANGE_ALT:
        return verify_change_alt();
        break;

    case WAIT_COMMAND:
        return false;
        break;

    // do commands (always return true)
    case MAV_CMD_DO_CHANGE_SPEED:
    case MAV_CMD_DO_SET_HOME:
    case MAV_CMD_DO_SET_SERVO:
    case MAV_CMD_DO_SET_RELAY:
    case MAV_CMD_DO_REPEAT_SERVO:
    case MAV_CMD_DO_REPEAT_RELAY:
    case MAV_CMD_DO_CONTROL_VIDEO:
    case MAV_CMD_DO_DIGICAM_CONFIGURE:
    case MAV_CMD_DO_DIGICAM_CONTROL:
    case MAV_CMD_DO_SET_CAM_TRIGG_DIST:
    case MAV_CMD_NAV_ROI:
    case MAV_CMD_DO_MOUNT_CONFIGURE:
    case MAV_CMD_DO_MOUNT_CONTROL:
        return true;

    default:
        // error message
        if (AP_Mission::is_nav_cmd(cmd)) {
            gcs_send_text_P(SEVERITY_HIGH,PSTR("verify_nav: Invalid or no current Nav cmd"));
        }else{
        gcs_send_text_P(SEVERITY_HIGH,PSTR("verify_conditon: Invalid or no current Condition cmd"));
    }
        // return true so that we do not get stuck at this command
        return true;
    }
}

/********************************************************************************/
//  Nav (Must) commands
/********************************************************************************/

static void do_RTL(void)
{
    control_mode    = RTL;
    prev_WP.content.location = current_loc;
    next_WP = rally_find_best_cmd(current_loc, home);

    if (g.loiter_radius < 0) {
        loiter.direction = -1;
    } else {
        loiter.direction = 1;
    }

    setup_glide_slope();

    if (should_log(MASK_LOG_MODE))
        Log_Write_Mode(control_mode);
}

static void do_takeoff(const AP_Mission::Mission_Command& cmd)
{
    set_next_WP(cmd);
    // pitch in deg, airspeed  m/s, throttle %, track WP 1 or 0
    takeoff_pitch_cd        = (int)cmd.p1 * 100;
    takeoff_altitude_cm     = next_WP.content.location.alt;
    next_WP.content.location.lat = home.lat + 10;
    next_WP.content.location.lng = home.lng + 10;
    takeoff_complete        = false;                            // set flag to use gps ground course during TO.  IMU will be doing yaw drift correction
    // Flag also used to override "on the ground" throttle disable
}

static void do_nav_wp(const AP_Mission::Mission_Command& cmd)
{
    set_next_WP(cmd);
}

static void do_land(const AP_Mission::Mission_Command& cmd)
{
    set_next_WP(cmd);
}

static void loiter_set_direction_wp(const AP_Mission::Mission_Command& cmd)
{
    if (cmd.content.location.flags.loiter_ccw) {
        loiter.direction = -1;
    } else {
        loiter.direction = 1;
    }
}

static void do_loiter_unlimited(const AP_Mission::Mission_Command& cmd)
{
    set_next_WP(cmd);
    loiter_set_direction_wp(cmd);
}

static void do_loiter_turns(const AP_Mission::Mission_Command& cmd)
{
    set_next_WP(cmd);
    loiter.total_cd = cmd.p1 * 36000UL;
    loiter_set_direction_wp(cmd);
}

static void do_loiter_time(const AP_Mission::Mission_Command& cmd)
{
    set_next_WP(cmd);
    // we set start_time_ms when we reach the waypoint
    loiter.start_time_ms = 0;
    loiter.time_max_ms = cmd.p1 * (uint32_t)1000;     // units are seconds
    loiter_set_direction_wp(cmd);
}

/********************************************************************************/
//  Verify Nav (Must) commands
/********************************************************************************/
static bool verify_takeoff()
{
    if (ahrs.yaw_initialised()) {
        if (steer_state.hold_course_cd == -1) {
            // save our current course to take off
            steer_state.hold_course_cd = ahrs.yaw_sensor;
            gcs_send_text_fmt(PSTR("Holding course %ld"), steer_state.hold_course_cd);
        }
    }

    if (steer_state.hold_course_cd != -1) {
        // call navigation controller for heading hold
        nav_controller->update_heading_hold(steer_state.hold_course_cd);
    } else {
        nav_controller->update_level_flight();        
    }

    // see if we have reached takeoff altitude
    if (adjusted_altitude_cm() > takeoff_altitude_cm) {
        steer_state.hold_course_cd = -1;
        takeoff_complete = true;
        next_WP.content.location = prev_WP.content.location = current_loc;
        return true;
    } else {
        return false;
    }
}

// we are executing a landing
static bool verify_land()
{
    // we don't 'verify' landing in the sense that it never completes,
    // so we don't verify command completion. Instead we use this to
    // adjust final landing parameters

    // Set land_complete if we are within 2 seconds distance or within
    // 3 meters altitude of the landing point
    if ((wp_distance <= (g.land_flare_sec*g_gps->ground_speed_cm*0.01f))
        || (adjusted_altitude_cm() <= next_WP.content.location.alt + g.land_flare_alt*100)) {

        land_complete = true;

        if (steer_state.hold_course_cd == -1) {
            // we have just reached the threshold of to flare for landing.
            // We now don't want to do any radical
            // turns, as rolling could put the wings into the runway.
            // To prevent further turns we set steer_state.hold_course_cd to the
            // current heading. Previously we set this to
            // crosstrack_bearing, but the xtrack bearing can easily
            // be quite large at this point, and that could induce a
            // sudden large roll correction which is very nasty at
            // this point in the landing.
            steer_state.hold_course_cd = ahrs.yaw_sensor;
            gcs_send_text_fmt(PSTR("Land Complete - Hold course %ld"), steer_state.hold_course_cd);
        }

        if (g_gps->ground_speed_cm*0.01f < 3.0) {
            // reload any airspeed or groundspeed parameters that may have
            // been set for landing. We don't do this till ground
            // speed drops below 3.0 m/s as otherwise we will change
            // target speeds too early.
            g.airspeed_cruise_cm.load();
            g.min_gndspeed_cm.load();
            aparm.throttle_cruise.load();
        }
    }

    if (steer_state.hold_course_cd != -1) {
        // recalc bearing error with hold_course;
        nav_controller->update_heading_hold(steer_state.hold_course_cd);
    } else {
        nav_controller->update_waypoint(prev_WP.content.location, next_WP.content.location);
    }
    return false;
}

static bool verify_nav_wp()
{
    steer_state.hold_course_cd = -1;

    nav_controller->update_waypoint(prev_WP.content.location, next_WP.content.location);

    // see if the user has specified a maximum distance to waypoint
    if (g.waypoint_max_radius > 0 && wp_distance > (uint16_t)g.waypoint_max_radius) {
        if (location_passed_point(current_loc, prev_WP.content.location, next_WP.content.location)) {
            // this is needed to ensure completion of the waypoint
            prev_WP.content.location = current_loc;
        }
        return false;
    }
    
    if (wp_distance <= nav_controller->turn_distance(g.waypoint_radius)) {
        gcs_send_text_fmt(PSTR("Reached Waypoint #%i dist %um"),
                          (unsigned)mission.get_current_nav_cmd().index,
                          (unsigned)get_distance(current_loc, next_WP.content.location));
        return true;
	}

    // have we flown past the waypoint?
    if (location_passed_point(current_loc, prev_WP.content.location, next_WP.content.location)) {
        gcs_send_text_fmt(PSTR("Passed Waypoint #%i dist %um"),
                          (unsigned)mission.get_current_nav_cmd().index,
                          (unsigned)get_distance(current_loc, next_WP.content.location));
        return true;
    }

    return false;
}

static bool verify_loiter_unlim()
{
    update_loiter();
    return false;
}

static bool verify_loiter_time()
{
    update_loiter();
    if (loiter.start_time_ms == 0) {
        if (nav_controller->reached_loiter_target()) {
            // we've reached the target, start the timer
            loiter.start_time_ms = millis();
        }
    } else if ((millis() - loiter.start_time_ms) > loiter.time_max_ms) {
        gcs_send_text_P(SEVERITY_LOW,PSTR("verify_nav: LOITER time complete"));
        return true;
    }
    return false;
}

static bool verify_loiter_turns()
{
    update_loiter();
    if (loiter.sum_cd > loiter.total_cd) {
        loiter.total_cd = 0;
        gcs_send_text_P(SEVERITY_LOW,PSTR("verify_nav: LOITER orbits complete"));
        // clear the command queue;
        return true;
    }
    return false;
}

static bool verify_RTL()
{
    update_loiter();
	if (wp_distance <= (uint32_t)max(g.waypoint_radius,0) || 
        nav_controller->reached_loiter_target()) {
			gcs_send_text_P(SEVERITY_LOW,PSTR("Reached home"));
			return true;
    } else {
        return false;
	}
}

/********************************************************************************/
//  Condition (May) commands
/********************************************************************************/

static void do_wait_delay(const AP_Mission::Mission_Command& cmd)
{
    condition_start = millis();
    condition_value  = cmd.content.location.lat * 1000;          // convert to milliseconds
}

static void do_change_alt(const AP_Mission::Mission_Command& cmd)
{
    condition_rate          = labs((int)cmd.content.location.lat);
    condition_value         = cmd.content.location.alt;
    if (condition_value < adjusted_altitude_cm()) {
        condition_rate = -condition_rate;
    }
    target_altitude_cm      = adjusted_altitude_cm() + (condition_rate / 10);                  // Divide by ten for 10Hz update
    next_WP.content.location.alt = condition_value;                                                                  // For future nav calculations
    offset_altitude_cm      = 0;                                                                                        // For future nav calculations
}

static void do_within_distance(const AP_Mission::Mission_Command& cmd)
{
    condition_value  = cmd.content.location.lat;
}

/********************************************************************************/
// Verify Condition (May) commands
/********************************************************************************/

static bool verify_wait_delay()
{
    if ((unsigned)(millis() - condition_start) > (unsigned)condition_value) {
        condition_value         = 0;
        return true;
    }
    return false;
}

static bool verify_change_alt()
{
    if( (condition_rate>=0 && adjusted_altitude_cm() >= condition_value) || 
        (condition_rate<=0 && adjusted_altitude_cm() <= condition_value)) {
        condition_value = 0;
        return true;
    }
    target_altitude_cm += condition_rate / 10;
    return false;
}

static bool verify_within_distance()
{
    if (wp_distance < max(condition_value,0)) {
        condition_value = 0;
        return true;
    }
    return false;
}

/********************************************************************************/
//  Do (Now) commands
/********************************************************************************/

static void do_loiter_at_location()
{
    if (g.loiter_radius < 0) {
        loiter.direction = -1;
    } else {
        loiter.direction = 1;
    }
    next_WP.content.location = current_loc;
}

static void do_change_speed(const AP_Mission::Mission_Command& cmd)
{
    switch (cmd.p1)
    {
    case 0:             // Airspeed
        if (cmd.content.location.alt > 0) {
            g.airspeed_cruise_cm.set(cmd.content.location.alt * 100);
            gcs_send_text_fmt(PSTR("Set airspeed %u m/s"), (unsigned)cmd.content.location.alt);
        }
        break;
    case 1:             // Ground speed
        gcs_send_text_fmt(PSTR("Set groundspeed %u"), (unsigned)cmd.content.location.alt);
        g.min_gndspeed_cm.set(cmd.content.location.alt * 100);
        break;
    }

    if (cmd.content.location.lat > 0) {
        gcs_send_text_fmt(PSTR("Set throttle %u"), (unsigned)cmd.content.location.lat);
        aparm.throttle_cruise.set(cmd.content.location.lat);
    }
}

static void do_set_home(const AP_Mission::Mission_Command& cmd)
{
    if (cmd.p1 == 1 && g_gps->status() == GPS::GPS_OK_FIX_3D) {
        init_home();
    } else {
        ahrs.set_home(cmd.content.location.lat, cmd.content.location.lng, cmd.content.location.alt);
        home_is_set = true;
    }
}

// do_take_picture - take a picture with the camera library
static void do_take_picture()
{
#if CAMERA == ENABLED
    camera.trigger_pic();
    if (should_log(MASK_LOG_CAMERA)) {
        Log_Write_Camera();
    }
#endif
}
