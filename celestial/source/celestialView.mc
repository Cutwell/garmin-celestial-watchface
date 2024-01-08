import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Position;
import Toybox.Time;

class celestialView extends WatchUi.WatchFace {
  var sunriseMinutes;
  var sunsetMinutes;

  // Drawables
  var Sun;
  var Moon;
  var BatteryFull;
  var BatteryHalf;
  var BatteryEmpty;
  var BatteryCharging;

  // Hack to track battery % over time and detect charging
  // Since the 1.4.0 target API doesn't support the .charging System Stat attribute
  var PrevBatteryPercentage;
  var BatteryChargingFlag;

  function initialize() {
    WatchFace.initialize();

    // Load drawable resources
    Sun = WatchUi.loadResource(Rez.Drawables.Sun);
    Moon = WatchUi.loadResource(Rez.Drawables.Moon);
    BatteryFull = WatchUi.loadResource(Rez.Drawables.BatteryFull);
    BatteryHalf = WatchUi.loadResource(Rez.Drawables.BatteryHalf);
    BatteryEmpty = WatchUi.loadResource(Rez.Drawables.BatteryEmpty);
    BatteryCharging = WatchUi.loadResource(Rez.Drawables.BatteryCharging);

    PrevBatteryPercentage = System.getSystemStats().battery;
    BatteryChargingFlag = false;
  }

  function fmod(x, y) {
    return x - Math.floor(x / y) * y;
  }

  function calculateSunriseSunset() {
    // Get Latitude/Longitude and current date
    var pos = Position.getInfo().position.toDegrees();
    var lat = pos[0];
    var lng = pos[1];
    var elevation = 0;
    var timestamp = Time.now().value(); // time since epoch

    var mean_solar_time =
      Math.ceil(
        timestamp / 86400.0 +
          2440587.5 -
          (2451545.0 + 0.0009) +
          69.184 / 86400.0
      ) +
      0.0009 -
      lng / 360.0;

    var solar_mean_anomaly_degrees = fmod(
      357.5291 + 0.98560028 * mean_solar_time,
      360
    );

    var solar_mean_anomaly_radians = Math.toRadians(solar_mean_anomaly_degrees);

    var ecliptic_longitude_radians = Math.toRadians(
      fmod(
        solar_mean_anomaly_degrees +
          (1.9148 * Math.sin(solar_mean_anomaly_radians) +
            0.02 * Math.sin(2 * solar_mean_anomaly_radians) +
            0.0003 * Math.sin(3 * solar_mean_anomaly_radians)) +
          180.0 +
          102.9372,
        360
      )
    );

    var julian_date_solar_transit =
      2451545.0 +
      mean_solar_time +
      0.0053 * Math.sin(solar_mean_anomaly_radians) -
      0.0069 * Math.sin(2 * ecliptic_longitude_radians);

    var sin_sun_declination =
      Math.sin(ecliptic_longitude_radians) * Math.sin(Math.toRadians(23.4397));

    var hour_angle_degrees = Math.toDegrees(
      Math.acos(
        (Math.sin(
          Math.toRadians(-0.833 - (2.076 * Math.sqrt(elevation)) / 60.0)
        ) -
          Math.sin(Math.toRadians(lat)) * sin_sun_declination) /
          (Math.cos(Math.toRadians(lat)) *
            Math.cos(Math.asin(sin_sun_declination)))
      )
    );

    var sunriseTimestamp =
      (julian_date_solar_transit - hour_angle_degrees / 360 - 2440587.5) *
      86400;
    var sunsetTimestamp =
      (julian_date_solar_transit + hour_angle_degrees / 360 - 2440587.5) *
      86400;
    var day_length = hour_angle_degrees / (180 / 24);

    var sunriseTime = Time.Gregorian.info(
      new Time.Moment(sunriseTimestamp.toNumber()),
      Time.FORMAT_SHORT
    );
    var sunsetTime = Time.Gregorian.info(
      new Time.Moment(sunsetTimestamp.toNumber()),
      Time.FORMAT_SHORT
    );

    return {
      "sunrise" => sunriseTime,
      "sunset" => sunsetTime,
      "day_length" => day_length,
    };
  }

  function updateTwilight() {
    var sunTimes = calculateSunriseSunset() as Dictionary;
    sunriseMinutes = (
      sunTimes["sunrise"].hour * 60 +
      sunTimes["sunrise"].min
    ).toFloat();
    sunsetMinutes = (
      sunTimes["sunset"].hour * 60 +
      sunTimes["sunset"].min
    ).toFloat();
  }

  // Load your resources here
  function onLayout(dc as Dc) as Void {}

  // Called when this View is brought to the foreground. Restore
  // the state of this View and prepare it to be shown. This includes
  // loading resources into memory.
  function onShow() as Void {
    updateTwilight();
  }

  // Update the view
  function onUpdate(dc as Dc) as Void {
    var screenWidth = dc.getWidth();
    var screenHeight = dc.getHeight();

    // draw white sky
    dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle(0, 0, screenWidth, screenHeight / 2);

    // draw celestial icon
    var celestialEvent = getSolarBody() as Dictionary;
    var pos =
      calculateApproxCelestialArc(
        screenWidth,
        screenHeight,
        celestialEvent["solarBody"].getWidth(),
        celestialEvent["solarBody"].getHeight(),
        celestialEvent["%"]
      ) as Array;
    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
    dc.drawBitmap(pos[0], pos[1], celestialEvent["solarBody"]);

    // Draw current date at top of page
    var today = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    var dateString = Lang.format("$1$/$2$", [
      today.day.format("%02d"),
      today.month.format("%02d"),
    ]);
    dc.drawText(
      screenWidth / 2,
      screenHeight * 0.15 - dc.getFontHeight(Graphics.FONT_MEDIUM),
      Graphics.FONT_MEDIUM,
      dateString,
      Graphics.TEXT_JUSTIFY_CENTER
    );

    // Draw landscape
    dc.fillRectangle(0, screenHeight / 2, screenWidth, screenHeight / 2);

    // Draw current time
    var timeString = Lang.format("$1$:$2$", [
      today.hour.format("%02d"),
      today.min.format("%02d"),
    ]);
    dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
    dc.drawText(
      screenWidth / 2,
      screenHeight * 0.7 - dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
      Graphics.FONT_NUMBER_MILD,
      timeString,
      Graphics.TEXT_JUSTIFY_CENTER
    );

    // Draw battery percentage and relevant icon
    var systemStatsBattery = System.getSystemStats().battery;
    var batteryString = Lang.format("$1$%", [systemStatsBattery.toNumber()]);
    var batteryImg = getBatteryIcon(systemStatsBattery);
    dc.drawText(
      screenWidth / 2 +
        (batteryImg.getWidth() +
          dc.getTextWidthInPixels(batteryString, Graphics.FONT_SMALL) * 0.75) /
          2,
      screenHeight * 0.9 - dc.getFontHeight(Graphics.FONT_SMALL),
      Graphics.FONT_SMALL,
      batteryString,
      Graphics.TEXT_JUSTIFY_CENTER
    );
    dc.drawBitmap(
      screenWidth / 2 -
        (batteryImg.getWidth() +
          dc.getTextWidthInPixels(batteryString, Graphics.FONT_SMALL) * 0.75) /
          2,
      screenHeight * 0.9 - dc.getFontHeight(Graphics.FONT_SMALL),
      batteryImg
    );
  }

  function getSolarBody() {
    var now = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    var nowMinutes = (now.hour * 60 + now.min).toFloat();

    if (nowMinutes >= sunriseMinutes && nowMinutes <= sunsetMinutes) {
      // is day
      return {
        "solarBody" => Sun,
        "%" => ((nowMinutes - sunriseMinutes) /
          (sunsetMinutes - sunriseMinutes)) *
        100,
      };
    } else if (nowMinutes < sunriseMinutes) {
      // is night (midnight -> now -> sunrise)
      // night % is between 50 and 100%
      return {
        "solarBody" => Moon,
        "%" => ((nowMinutes / sunriseMinutes) * 100) / 2 + 50,
      };
    } else if (nowMinutes > sunsetMinutes) {
      // is night (sunset -> now -> midnight)
      // night % is between 0 and 50%
      return {
        "solarBody" => Moon,
        "%" => (((nowMinutes - sunsetMinutes) / (24 * 60 - sunsetMinutes)) *
          100) /
        2,
      };
    } else {
      return {
        "solarBody" => Sun,
        "%" => 0,
      };
    }
  }

  function calculateApproxCelestialArc(
    screenWidth,
    screenHeight,
    imgWidth,
    imgHeight,
    percentage
  ) {
    // calculate approximate location of current celestial body in the sky

    var midX = screenWidth / 2 - imgWidth / 2;
    var midY = screenHeight / 4 - imgHeight / 2;

    // bucketed positions
    var posBucket = [
      [midX - screenWidth / 4, screenHeight / 2 - imgHeight / 2], // rising
      [midX - screenWidth / 4 / 2, screenHeight / 3 - imgHeight / 2], // 25%
      [midX, midY], // midday / midnight
      [midX + screenWidth / 4 / 2, screenHeight / 3 - imgHeight / 2], // 75%
      [midX + screenWidth / 4, screenHeight / 2 - imgHeight / 2], // setting
    ];

    var cumulative_percentage = 0;
    for (var index = 0; index < posBucket.size(); index++) {
      cumulative_percentage += 100 / posBucket.size();
      if (percentage <= cumulative_percentage) {
        return posBucket[index];
      }
    }

    // else, return the last index
    return posBucket[posBucket.size() - 1];
  }

  function getBatteryIcon(curr_percentage) {
    if (curr_percentage > PrevBatteryPercentage) {
      BatteryChargingFlag = true;
    } else if (curr_percentage < PrevBatteryPercentage) {
      BatteryChargingFlag = false;
    }

    PrevBatteryPercentage = curr_percentage;
    if (curr_percentage == 100) {
      // show battery full if 100% (even if charging)
      return BatteryFull;
    } else if (BatteryChargingFlag) {
      // show charging if battery level is rising
      return BatteryCharging;
    } else if (curr_percentage < 10) {
      // show empty if < 10%
      return BatteryEmpty;
    } else if (curr_percentage < 80) {
      // show half-charged if between 10% and 80%
      return BatteryHalf;
    } else {
      // show full if > 80%
      return BatteryFull;
    }
  }

  // Called when this View is removed from the screen. Save the
  // state of this View here. This includes freeing resources from
  // memory.
  function onHide() as Void {}

  // The user has just looked at their watch. Timers and animations may be started here.
  function onExitSleep() as Void {
    updateTwilight();
  }

  // Terminate any active timers and prepare for slow updates.
  function onEnterSleep() as Void {}
}
