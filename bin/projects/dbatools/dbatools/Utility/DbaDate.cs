using System;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// A dbatools-internal datetime wrapper for neater display
    /// </summary>
    public class DbaDate : DbaDateTimeBase
    {
        #region Constructors
        /// <summary>
        /// Constructs a generic timestamp object wrapper from an input timestamp object.
        /// </summary>
        /// <param name="Timestamp">The timestamp to wrap</param>
        public DbaDate(DateTime Timestamp)
        {
            _timestamp = Timestamp;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="ticks"></param>
        public DbaDate(long ticks)
        {
            _timestamp = new DateTime(ticks);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="ticks"></param>
        /// <param name="kind"></param>
        public DbaDate(long ticks, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(ticks, kind);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        public DbaDate(int year, int month, int day)
        {
            _timestamp = new DateTime(year, month, day);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="calendar"></param>
        public DbaDate(int year, int month, int day, System.Globalization.Calendar calendar)
        {
            _timestamp = new DateTime(year, month, day, calendar);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="hour"></param>
        /// <param name="minute"></param>
        /// <param name="second"></param>
        public DbaDate(int year, int month, int day, int hour, int minute, int second)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="hour"></param>
        /// <param name="minute"></param>
        /// <param name="second"></param>
        /// <param name="kind"></param>
        public DbaDate(int year, int month, int day, int hour, int minute, int second, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, kind);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="hour"></param>
        /// <param name="minute"></param>
        /// <param name="second"></param>
        /// <param name="calendar"></param>
        public DbaDate(int year, int month, int day, int hour, int minute, int second, System.Globalization.Calendar calendar)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, calendar);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="hour"></param>
        /// <param name="minute"></param>
        /// <param name="second"></param>
        /// <param name="millisecond"></param>
        public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="hour"></param>
        /// <param name="minute"></param>
        /// <param name="second"></param>
        /// <param name="millisecond"></param>
        /// <param name="kind"></param>
        public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, kind);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="hour"></param>
        /// <param name="minute"></param>
        /// <param name="second"></param>
        /// <param name="millisecond"></param>
        /// <param name="calendar"></param>
        public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        /// <param name="hour"></param>
        /// <param name="minute"></param>
        /// <param name="second"></param>
        /// <param name="millisecond"></param>
        /// <param name="calendar"></param>
        /// <param name="kind"></param>
        public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar, kind);
        }
        #endregion Constructors

        /// <summary>
        /// Provids the default-formated string, using the defined default formatting.
        /// </summary>
        /// <returns>Formatted datetime-string</returns>
        public override string ToString()
        {
            if (UtilityHost.DisableCustomDateTime) { return _timestamp.ToString(); }
            return _timestamp.ToString(UtilityHost.FormatDate);
        }

        #region Implicit Conversions
        /// <summary>
        /// Implicitly convert to DateTime
        /// </summary>
        /// <param name="Base">The source object to convert</param>
        public static implicit operator DateTime(DbaDate Base)
        {
            return Base.GetBaseObject();
        }

        /// <summary>
        /// Implicitly convert from DateTime
        /// </summary>
        /// <param name="Base">The object to convert</param>
        public static implicit operator DbaDate(DateTime Base)
        {
            return new DbaDate(Base);
        }

        /// <summary>
        /// Implicitly convert to DbaDate
        /// </summary>
        /// <param name="Base">The source object to convert</param>
        public static implicit operator DbaDateTime(DbaDate Base)
        {
            return new DbaDateTime(Base.GetBaseObject());
        }

        /// <summary>
        /// Implicitly convert to DbaTime
        /// </summary>
        /// <param name="Base">The source object to convert</param>
        public static implicit operator DbaTime(DbaDate Base)
        {
            return new DbaTime(Base.GetBaseObject());
        }
        #endregion Implicit Conversions

        #region Statics
        /// <summary>
        /// Generates a DbaDate object based off DateTime object. Will be null if Base is the start value (Tickes == 0).
        /// </summary>
        /// <param name="Base">The Datetime to base it off</param>
        /// <returns>The object to generate (or null)</returns>
        public static DbaDate Generate(DateTime Base)
        {
            if (Base.Ticks == 0)
                return null;
            else
                return new DbaDate(Base);
        }
        #endregion Statics
    }
}