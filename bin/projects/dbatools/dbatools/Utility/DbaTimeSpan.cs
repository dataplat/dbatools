using System;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// A wrapper class, encapsuling a regular TimeSpan object. Used to provide custom timespan display.
    /// </summary>
    public class DbaTimeSpan : IComparable, IComparable<TimeSpan>, IComparable<DbaTimeSpan>, IEquatable<TimeSpan>
    {
        internal TimeSpan _timespan;

        #region Properties
        /// <summary>
        /// Gets the days component of the time interval represented by the current TimeSpan structure.
        /// </summary>
        public int Days
        {
            get
            {
                return _timespan.Days;
            }
        }

        /// <summary>
        /// Gets the hours component of the time interval represented by the current TimeSpan structure.
        /// </summary>
        public int Hours
        {
            get
            {
                return _timespan.Hours;
            }
        }

        /// <summary>
        /// Gets the milliseconds component of the time interval represented by the current TimeSpan structure.
        /// </summary>
        public int Milliseconds
        {
            get
            {
                return _timespan.Milliseconds;
            }
        }

        /// <summary>
        /// Gets the minutes component of the time interval represented by the current TimeSpan structure.
        /// </summary>
        public int Minutes
        {
            get
            {
                return _timespan.Minutes;
            }
        }

        /// <summary>
        /// Gets the seconds component of the time interval represented by the current TimeSpan structure.
        /// </summary>
        public int Seconds
        {
            get
            {
                return _timespan.Seconds;
            }
        }

        /// <summary>
        /// Gets the number of ticks that represent the value of the current TimeSpan structure.
        /// </summary>
        public long Ticks
        {
            get
            {
                return _timespan.Ticks;
            }
        }

        /// <summary>
        /// Gets the value of the current TimeSpan structure expressed in whole and fractional days.
        /// </summary>
        public double TotalDays
        {
            get
            {
                return _timespan.TotalDays;
            }
        }

        /// <summary>
        /// Gets the value of the current TimeSpan structure expressed in whole and fractional hours.
        /// </summary>
        public double TotalHours
        {
            get
            {
                return _timespan.TotalHours;
            }
        }

        /// <summary>
        /// Gets the value of the current TimeSpan structure expressed in whole and fractional milliseconds.
        /// </summary>
        public double TotalMilliseconds
        {
            get
            {
                return _timespan.TotalMilliseconds;
            }
        }

        /// <summary>
        /// Gets the value of the current TimeSpan structure expressed in whole and fractional minutes.
        /// </summary>
        public double TotalMinutes
        {
            get
            {
                return _timespan.TotalMinutes;
            }
        }

        /// <summary>
        /// Gets the value of the current TimeSpan structure expressed in whole and fractional seconds.
        /// </summary>
        public double TotalSeconds
        {
            get
            {
                return _timespan.TotalSeconds;
            }
        }
        #endregion Properties

        #region Constructors
        /// <summary>
        /// 
        /// </summary>
        /// <param name="Timespan"></param>
        public DbaTimeSpan(TimeSpan Timespan)
        {
            _timespan = Timespan;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="ticks"></param>
        public DbaTimeSpan(long ticks)
        {
            _timespan = new TimeSpan(ticks);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="hours"></param>
        /// <param name="minutes"></param>
        /// <param name="seconds"></param>
        public DbaTimeSpan(int hours, int minutes, int seconds)
        {
            _timespan = new TimeSpan(hours, minutes, seconds);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="days"></param>
        /// <param name="hours"></param>
        /// <param name="minutes"></param>
        /// <param name="seconds"></param>
        public DbaTimeSpan(int days, int hours, int minutes, int seconds)
        {
            _timespan = new TimeSpan(days, hours, minutes, seconds);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="days"></param>
        /// <param name="hours"></param>
        /// <param name="minutes"></param>
        /// <param name="seconds"></param>
        /// <param name="milliseconds"></param>
        public DbaTimeSpan(int days, int hours, int minutes, int seconds, int milliseconds)
        {
            _timespan = new TimeSpan(days, hours, minutes, seconds, milliseconds);
        }
        #endregion Constructors

        #region Methods
        /// <summary>
        /// 
        /// </summary>
        /// <param name="ts"></param>
        /// <returns></returns>
        public TimeSpan Add(TimeSpan ts)
        {
            return _timespan.Add(ts);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public int CompareTo(System.Object value)
        {
            return _timespan.CompareTo(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public int CompareTo(TimeSpan value)
        {
            return _timespan.CompareTo(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public int CompareTo(DbaTimeSpan value)
        {
            return _timespan.CompareTo(value.GetBaseObject());
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public TimeSpan Duration()
        {
            return _timespan.Duration();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public override bool Equals(System.Object value)
        {
            return _timespan.Equals(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="obj"></param>
        /// <returns></returns>
        public bool Equals(TimeSpan obj)
        {
            return _timespan.Equals(obj);
        }

        /// <summary>
        /// Returns the wrapped base object
        /// </summary>
        /// <returns>The base object</returns>
        public TimeSpan GetBaseObject()
        {
            return _timespan;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public override int GetHashCode()
        {
            return _timespan.GetHashCode();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public TimeSpan Negate()
        {
            return _timespan.Negate();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="ts"></param>
        /// <returns></returns>
        public TimeSpan Subtract(TimeSpan ts)
        {
            return _timespan.Subtract(ts);
        }

        /// <summary>
        /// Returns the default string representation of the TimeSpan object
        /// </summary>
        /// <returns>The string representation of the DbaTimeSpan object</returns>
        public override string ToString()
        {
            if (UtilityHost.DisableCustomTimeSpan) { return _timespan.ToString(); }
            else if (_timespan.Ticks % 10000000 == 0) { return _timespan.ToString(); }
            else
            {
                string temp = _timespan.ToString();

                if (_timespan.TotalSeconds < 10) { temp = temp.Substring(0, temp.LastIndexOf(".") + 3); }
                else if (_timespan.TotalSeconds < 100) { temp = temp.Substring(0, temp.LastIndexOf(".") + 2); }
                else { temp = temp.Substring(0, temp.LastIndexOf(".")); }

                return temp;
            }
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <returns></returns>
        public string ToString(string format)
        {
            return _timespan.ToString(format);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <param name="formatProvider"></param>
        /// <returns></returns>
        public string ToString(string format, System.IFormatProvider formatProvider)
        {
            return _timespan.ToString(format, formatProvider);
        }
        #endregion Methods

        #region Implicit Operators
        /// <summary>
        /// Implicitly converts a DbaTimeSpan object into a TimeSpan object
        /// </summary>
        /// <param name="Base">The original object to revert</param>
        public static implicit operator TimeSpan(DbaTimeSpan Base)
        {
            try { return Base.GetBaseObject(); }
            catch { }
            return new TimeSpan();
        }

        /// <summary>
        /// Implicitly converts a TimeSpan object into a DbaTimeSpan object
        /// </summary>
        /// <param name="Base">The original object to wrap</param>
        public static implicit operator DbaTimeSpan(TimeSpan Base)
        {
            return new DbaTimeSpan(Base);
        }
        #endregion Implicit Operators
    }
}