using System;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Base class for wrapping around a DateTime object
    /// </summary>
    public class DbaDateTimeBase : IComparable, IComparable<DateTime>, IEquatable<DateTime> // IFormattable,
    {
        #region Properties
        /// <summary>
        /// The core resource, containing the actual timestamp
        /// </summary>
        internal DateTime _timestamp;

        /// <summary>
        /// Gets the date component of this instance.
        /// </summary>
        public DateTime Date
        {
            get { return _timestamp.Date; }
        }

        /// <summary>
        /// Gets the day of the month represented by this instance.
        /// </summary>
        public int Day
        {
            get { return _timestamp.Day; }
        }

        /// <summary>
        /// Gets the day of the week represented by this instance.
        /// </summary>
        public DayOfWeek DayOfWeek
        {
            get { return _timestamp.DayOfWeek; }
        }

        /// <summary>
        /// Gets the day of the year represented by this instance.
        /// </summary>
        public int DayOfYear
        {
            get { return _timestamp.DayOfYear; }
        }

        /// <summary>
        /// Gets the hour component of the date represented by this instance.
        /// </summary>
        public int Hour
        {
            get { return _timestamp.Hour; }
        }

        /// <summary>
        /// Gets a value that indicates whether the time represented by this instance is based on local time, Coordinated Universal Time (UTC), or neither.
        /// </summary>
        public DateTimeKind Kind
        {
            get { return _timestamp.Kind; }
        }

        /// <summary>
        /// Gets the milliseconds component of the date represented by this instance.
        /// </summary>
        public int Millisecond
        {
            get { return _timestamp.Millisecond; }
        }

        /// <summary>
        /// Gets the minute component of the date represented by this instance.
        /// </summary>
        public int Minute
        {
            get { return _timestamp.Minute; }
        }

        /// <summary>
        /// Gets the month component of the date represented by this instance.
        /// </summary>
        public int Month
        {
            get { return _timestamp.Month; }
        }

        /// <summary>
        /// Gets the seconds component of the date represented by this instance.
        /// </summary>
        public int Second
        {
            get { return _timestamp.Second; }
        }

        /// <summary>
        /// Gets the number of ticks that represent the date and time of this instance.
        /// </summary>
        public long Ticks
        {
            get { return _timestamp.Ticks; }
        }

        /// <summary>
        /// Gets the time of day for this instance.
        /// </summary>
        public TimeSpan TimeOfDay
        {
            get { return _timestamp.TimeOfDay; }
        }

        /// <summary>
        /// Gets the year component of the date represented by this instance.
        /// </summary>
        public int Year
        {
            get { return _timestamp.Year; }
        }
        #endregion Properties

        #region Constructors
        /// <summary>
        /// Constructor that should never be called, since this class should never be instantiated. It's there for implicit calls on child classes.
        /// </summary>
        public DbaDateTimeBase()
        {

        }

        /// <summary>
        /// Constructs a generic timestamp object wrapper from an input timestamp object.
        /// </summary>
        /// <param name="Timestamp">The timestamp to wrap</param>
        public DbaDateTimeBase(DateTime Timestamp)
        {
            _timestamp = Timestamp;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="ticks"></param>
        public DbaDateTimeBase(long ticks)
        {
            _timestamp = new DateTime(ticks);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="ticks"></param>
        /// <param name="kind"></param>
        public DbaDateTimeBase(long ticks, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(ticks, kind);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="year"></param>
        /// <param name="month"></param>
        /// <param name="day"></param>
        public DbaDateTimeBase(int year, int month, int day)
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
        public DbaDateTimeBase(int year, int month, int day, System.Globalization.Calendar calendar)
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
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second)
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
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, System.DateTimeKind kind)
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
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, System.Globalization.Calendar calendar)
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
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond)
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
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.DateTimeKind kind)
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
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar)
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
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar, kind);
        }
        #endregion Constructors

        #region Methods
        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime Add(TimeSpan value)
        {
            return _timestamp.Add(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddDays(double value)
        {
            return _timestamp.AddDays(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddHours(double value)
        {
            return _timestamp.AddHours(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddMilliseconds(double value)
        {
            return _timestamp.AddMilliseconds(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddMinutes(double value)
        {
            return _timestamp.AddMinutes(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="months"></param>
        /// <returns></returns>
        public DateTime AddMonths(int months)
        {
            return _timestamp.AddMonths(months);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddSeconds(double value)
        {
            return _timestamp.AddSeconds(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddTicks(long value)
        {
            return _timestamp.AddTicks(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddYears(int value)
        {
            return _timestamp.AddYears(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public int CompareTo(System.Object value)
        {
            return _timestamp.CompareTo(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public int CompareTo(DateTime value)
        {
            return _timestamp.CompareTo(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public override bool Equals(System.Object value)
        {
            return _timestamp.Equals(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public bool Equals(DateTime value)
        {
            return _timestamp.Equals(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public string[] GetDateTimeFormats()
        {
            return _timestamp.GetDateTimeFormats();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="provider"></param>
        /// <returns></returns>
        public string[] GetDateTimeFormats(System.IFormatProvider provider)
        {
            return _timestamp.GetDateTimeFormats(provider);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <returns></returns>
        public string[] GetDateTimeFormats(char format)
        {
            return _timestamp.GetDateTimeFormats(format);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <param name="provider"></param>
        /// <returns></returns>
        public string[] GetDateTimeFormats(char format, System.IFormatProvider provider)
        {
            return _timestamp.GetDateTimeFormats(format, provider);
        }

        /// <summary>
        /// Retrieve base DateTime object, this is a wrapper for
        /// </summary>
        /// <returns>Base DateTime object</returns>
        public DateTime GetBaseObject()
        {
            return _timestamp;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public override int GetHashCode()
        {
            return _timestamp.GetHashCode();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public System.TypeCode GetTypeCode()
        {
            return _timestamp.GetTypeCode();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public bool IsDaylightSavingTime()
        {
            return _timestamp.IsDaylightSavingTime();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public TimeSpan Subtract(DateTime value)
        {
            return _timestamp.Subtract(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime Subtract(TimeSpan value)
        {
            return _timestamp.Subtract(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public long ToBinary()
        {
            return _timestamp.ToBinary();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public long ToFileTime()
        {
            return _timestamp.ToFileTime();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public long ToFileTimeUtc()
        {
            return _timestamp.ToFileTimeUtc();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public DateTime ToLocalTime()
        {
            return _timestamp.ToLocalTime();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public string ToLongDateString()
        {
            return _timestamp.ToLongDateString();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public string ToLongTimeString()
        {
            return _timestamp.ToLongTimeString();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public double ToOADate()
        {
            return _timestamp.ToOADate();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public string ToShortDateString()
        {
            return _timestamp.ToShortDateString();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public string ToShortTimeString()
        {
            return _timestamp.ToShortTimeString();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <returns></returns>
        public string ToString(string format)
        {
            return _timestamp.ToString(format);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="provider"></param>
        /// <returns></returns>
        public string ToString(System.IFormatProvider provider)
        {
            return _timestamp.ToString(provider);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <param name="provider"></param>
        /// <returns></returns>
        public string ToString(string format, System.IFormatProvider provider)
        {
            return _timestamp.ToString(format, provider);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public DateTime ToUniversalTime()
        {
            return _timestamp.ToUniversalTime();
        }


        #endregion Methods

        #region Operators
        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp"></param>
        /// <param name="Duration"></param>
        /// <returns></returns>
        public static DbaDateTimeBase operator +(DbaDateTimeBase Timestamp, TimeSpan Duration)
        {
            return Timestamp.Add(Duration);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp"></param>
        /// <param name="Duration"></param>
        /// <returns></returns>
        public static DbaDateTimeBase operator -(DbaDateTimeBase Timestamp, TimeSpan Duration)
        {
            return Timestamp.Subtract(Duration);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp1"></param>
        /// <param name="Timestamp2"></param>
        /// <returns></returns>
        public static bool operator ==(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
        {
            return (Timestamp1.GetBaseObject().Equals(Timestamp2.GetBaseObject()));
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp1"></param>
        /// <param name="Timestamp2"></param>
        /// <returns></returns>
        public static bool operator !=(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
        {
            return (!Timestamp1.GetBaseObject().Equals(Timestamp2.GetBaseObject()));
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp1"></param>
        /// <param name="Timestamp2"></param>
        /// <returns></returns>
        public static bool operator >(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
        {
            return Timestamp1.GetBaseObject() > Timestamp2.GetBaseObject();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp1"></param>
        /// <param name="Timestamp2"></param>
        /// <returns></returns>
        public static bool operator <(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
        {
            return Timestamp1.GetBaseObject() < Timestamp2.GetBaseObject();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp1"></param>
        /// <param name="Timestamp2"></param>
        /// <returns></returns>
        public static bool operator >=(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
        {
            return Timestamp1.GetBaseObject() >= Timestamp2.GetBaseObject();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timestamp1"></param>
        /// <param name="Timestamp2"></param>
        /// <returns></returns>
        public static bool operator <=(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
        {
            return Timestamp1.GetBaseObject() <= Timestamp2.GetBaseObject();
        }
        #endregion Operators

        #region Implicit Conversions
        /// <summary>
        /// Implicitly convert DbaDateTimeBase to DateTime
        /// </summary>
        /// <param name="Base">The source object to convert</param>
        public static implicit operator DateTime(DbaDateTimeBase Base)
        {
            return Base.GetBaseObject();
        }

        /// <summary>
        /// Implicitly convert DateTime to DbaDateTimeBase
        /// </summary>
        /// <param name="Base">The object to convert</param>
        public static implicit operator DbaDateTimeBase(DateTime Base)
        {
            return new DbaDateTimeBase(Base.Ticks, Base.Kind);
        }
        #endregion Implicit Conversions
    }
}