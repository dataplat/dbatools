using System;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// Base class for wrapping around a DateTime object
    /// </summary>
    public partial class DbaDateTimeBase : IComparable, IComparable<DateTime>, IEquatable<DateTime> // IFormattable,
    {
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
        /// Parses a string into a datetime object.
        /// </summary>
        /// <param name="Time">The time-string to parse</param>
        public DbaDateTimeBase(string Time)
        {
            _timestamp = ParseDateTime(Time);
        }

        /// <summary>
        /// Initializes a new instance from the specified tick count.
        /// </summary>
        /// <param name="ticks">The number of ticks that represent the timestamp.</param>
        public DbaDateTimeBase(long ticks)
        {
            _timestamp = new DateTime(ticks);
        }

        /// <summary>
        /// Initializes a new instance from the specified tick count and kind.
        /// </summary>
        /// <param name="ticks">The number of ticks that represent the timestamp.</param>
        /// <param name="kind">The value that indicates whether the timestamp is local, UTC, or unspecified.</param>
        public DbaDateTimeBase(long ticks, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(ticks, kind);
        }

        /// <summary>
        /// Initializes a new instance from the specified year, month, and day.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        public DbaDateTimeBase(int year, int month, int day)
        {
            _timestamp = new DateTime(year, month, day);
        }

        /// <summary>
        /// Initializes a new instance from the specified date using a calendar.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="calendar">The calendar used to interpret the date components.</param>
        public DbaDateTimeBase(int year, int month, int day, System.Globalization.Calendar calendar)
        {
            _timestamp = new DateTime(year, month, day, calendar);
        }

        /// <summary>
        /// Initializes a new instance from the specified date and time.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="hour">The hour component.</param>
        /// <param name="minute">The minute component.</param>
        /// <param name="second">The second component.</param>
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second);
        }

        /// <summary>
        /// Initializes a new instance from the specified date, time, and kind.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="hour">The hour component.</param>
        /// <param name="minute">The minute component.</param>
        /// <param name="second">The second component.</param>
        /// <param name="kind">The value that indicates whether the timestamp is local, UTC, or unspecified.</param>
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, kind);
        }

        /// <summary>
        /// Initializes a new instance from the specified date and time using a calendar.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="hour">The hour component.</param>
        /// <param name="minute">The minute component.</param>
        /// <param name="second">The second component.</param>
        /// <param name="calendar">The calendar used to interpret the date and time components.</param>
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, System.Globalization.Calendar calendar)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, calendar);
        }

        /// <summary>
        /// Initializes a new instance from the specified date and time including milliseconds.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="hour">The hour component.</param>
        /// <param name="minute">The minute component.</param>
        /// <param name="second">The second component.</param>
        /// <param name="millisecond">The millisecond component.</param>
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond);
        }

        /// <summary>
        /// Initializes a new instance from the specified date, time, milliseconds, and kind.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="hour">The hour component.</param>
        /// <param name="minute">The minute component.</param>
        /// <param name="second">The second component.</param>
        /// <param name="millisecond">The millisecond component.</param>
        /// <param name="kind">The value that indicates whether the timestamp is local, UTC, or unspecified.</param>
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, kind);
        }

        /// <summary>
        /// Initializes a new instance from the specified date and time including milliseconds using a calendar.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="hour">The hour component.</param>
        /// <param name="minute">The minute component.</param>
        /// <param name="second">The second component.</param>
        /// <param name="millisecond">The millisecond component.</param>
        /// <param name="calendar">The calendar used to interpret the date and time components.</param>
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar);
        }

        /// <summary>
        /// Initializes a new instance from the specified date, time, milliseconds, calendar, and kind.
        /// </summary>
        /// <param name="year">The year component.</param>
        /// <param name="month">The month component.</param>
        /// <param name="day">The day component.</param>
        /// <param name="hour">The hour component.</param>
        /// <param name="minute">The minute component.</param>
        /// <param name="second">The second component.</param>
        /// <param name="millisecond">The millisecond component.</param>
        /// <param name="calendar">The calendar used to interpret the date and time components.</param>
        /// <param name="kind">The value that indicates whether the timestamp is local, UTC, or unspecified.</param>
        public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar, System.DateTimeKind kind)
        {
            _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar, kind);
        }
    }
}
