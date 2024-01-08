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
    var quotient = x / y;
    var floorQuotient = Math.floor(quotient);
    return x - floorQuotient * y;
  }

  function calculateSunriseSunset() {
    // Get Latitude/Longitude and current date
    var pos = Position.getInfo().position.toDegrees();
    var lat = pos[0];
    var lng = pos[1];
    System.println("Lat " + lat);
    System.println("Long " + lng);
    var elevation = 0;
    var timestamp = Time.now().value(); // time since epoch

    var julian_date = timestamp / 86400.0 + 2440587.5;

    var julian_day = Math.ceil(
      julian_date - (2451545.0 + 0.0009) + 69.184 / 86400.0
    );

    var mean_solar_time = julian_day + 0.0009 - lng / 360.0;

    var solar_mean_anomaly_degrees = fmod(
      357.5291 + 0.98560028 * mean_solar_time,
      360
    );

    var solar_mean_anomaly_radians = Math.toRadians(solar_mean_anomaly_degrees);

    var center_degrees =
      1.9148 * Math.sin(solar_mean_anomaly_radians) +
      0.02 * Math.sin(2 * solar_mean_anomaly_radians) +
      0.0003 * Math.sin(3 * solar_mean_anomaly_radians);

    var ecliptic_longitude_degrees = fmod(
      solar_mean_anomaly_degrees + center_degrees + 180.0 + 102.9372,
      360
    );

    var ecliptic_longitude_radians = Math.toRadians(ecliptic_longitude_degrees);

    var julian_date_solar_transit =
      2451545.0 +
      mean_solar_time +
      0.0053 * Math.sin(solar_mean_anomaly_radians) -
      0.0069 * Math.sin(2 * ecliptic_longitude_radians);

    var sin_sun_declination =
      Math.sin(ecliptic_longitude_radians) * Math.sin(Math.toRadians(23.4397));

    var cos_sun_declination = Math.cos(Math.asin(sin_sun_declination));

    var cos_hour_angle =
      (Math.sin(
        Math.toRadians(-0.833 - (2.076 * Math.sqrt(elevation)) / 60.0)
      ) -
        Math.sin(Math.toRadians(lat)) * sin_sun_declination) /
      (Math.cos(Math.toRadians(lat)) * cos_sun_declination);

    var hour_angle_radians = Math.acos(cos_hour_angle);

    var hour_angle_degrees = Math.toDegrees(hour_angle_radians);

    var julian_rise = julian_date_solar_transit - hour_angle_degrees / 360;
    var julian_set = julian_date_solar_transit + hour_angle_degrees / 360;

    var sunriseTimestamp = (julian_rise - 2440587.5) * 86400;
    var sunsetTimestamp = (julian_set - 2440587.5) * 86400;
    var day_length = hour_angle_degrees / (180 / 24);

    var sunriseMoment = new Time.Moment(sunriseTimestamp.toNumber());
    var sunsetMoment = new Time.Moment(sunsetTimestamp.toNumber());

    var sunriseTime = Time.Gregorian.info(sunriseMoment, Time.FORMAT_SHORT);
    var sunsetTime = Time.Gregorian.info(sunsetMoment, Time.FORMAT_SHORT);

    System.println("Sunrise " + sunriseTime.hour + ":" + sunriseTime.min);
    System.println("Sunset " + sunsetTime.hour + ":" + sunsetTime.min);
    System.println("Day Length " + day_length);
    System.println("---------");

    return {
      "sunrise" => sunriseTime,
      "sunset" => sunsetTime,
      "day_length" => day_length,
    };
  }

  function updateTwilight() {
    var sunTimes = calculateSunriseSunset() as Dictionary;

    var sunriseTime = sunTimes["sunrise"];
    var sunsetTime = sunTimes["sunset"];

    sunriseMinutes = sunriseTime.hour * 60 + sunriseTime.min;
    sunsetMinutes = sunsetTime.hour * 60 + sunsetTime.min;

    sunriseMinutes = sunriseMinutes.toFloat();
    sunsetMinutes = sunsetMinutes.toFloat();
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
    var celestialImg = celestialEvent["solarBody"];
    var pos =
      calculateApproxCelestialArc(
        screenWidth,
        screenHeight,
        celestialImg.getWidth(),
        celestialImg.getHeight(),
        celestialEvent["%"]
      ) as Array;
    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
    dc.drawBitmap(pos[0], pos[1], celestialImg);

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
          dc.getTextWidthInPixels(batteryString, Graphics.FONT_SMALL)*0.75) /
          2,
      screenHeight * 0.9 - dc.getFontHeight(Graphics.FONT_SMALL),
      Graphics.FONT_SMALL,
      batteryString,
      Graphics.TEXT_JUSTIFY_CENTER
    );
    dc.drawBitmap(
      screenWidth / 2 -
        (batteryImg.getWidth() +
          dc.getTextWidthInPixels(batteryString, Graphics.FONT_SMALL)*0.75) /
          2,
      screenHeight * 0.9 - dc.getFontHeight(Graphics.FONT_SMALL),
      batteryImg
    );
  }

  function getSolarBody() {
    var now = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    var nowMinutes = now.hour * 60 + now.min;
    nowMinutes = nowMinutes.toFloat();

    if (nowMinutes >= sunriseMinutes && nowMinutes <= sunsetMinutes) {
      // is day
      var day_percentage =
        ((nowMinutes - sunriseMinutes) / (sunsetMinutes - sunriseMinutes)) *
        100;

      return {
        "solarBody" => Sun,
        "%" => day_percentage,
      };
    } else if (nowMinutes < sunriseMinutes) {
      // is night (midnight -> now -> sunrise)
      // night % is between 50 and 100%
      var night_percentage = ((nowMinutes / sunriseMinutes) * 100) / 2 + 50;

      return {
        "solarBody" => Moon,
        "%" => night_percentage,
      };
    } else if (nowMinutes > sunsetMinutes) {
      // is night (sunset -> now -> midnight)
      // night % is between 0 and 50%
      var night_percentage =
        (((nowMinutes - sunsetMinutes) / (24 * 60 - sunsetMinutes)) * 100) / 2;

      return {
        "solarBody" => Moon,
        "%" => night_percentage,
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

    var icon;
    if (curr_percentage == 100) {
      // show battery full if 100% (even if charging)
      icon = BatteryFull;
    } else if (BatteryChargingFlag) {
      // show charging if battery level is rising
      icon = BatteryCharging;
    } else if (curr_percentage < 10) {
      // show empty if < 10%
      icon = BatteryEmpty;
    } else if (curr_percentage < 80) {
      // show half-charged if between 10% and 80%
      icon = BatteryHalf;
    } else {
      // show full if > 80%
      icon = BatteryFull;
    }

    PrevBatteryPercentage = curr_percentage;
    return icon;
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
