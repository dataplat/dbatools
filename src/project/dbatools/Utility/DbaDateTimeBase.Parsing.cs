using System;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Utility
{
    public partial class DbaDateTimeBase
    {
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

        /// <summary>
        /// Parses input string into datetime
        /// </summary>
        /// <param name="Value">The string to parse</param>
        /// <returns>The resultant datetime.</returns>
        internal static DateTime ParseDateTime(string Value)
        {
            if (String.IsNullOrWhiteSpace(Value))
                throw new ArgumentNullException("Cannot parse empty string");

            try { return DateTime.Parse(Value, CultureInfo.CurrentCulture); }
            catch { }
            try { return DateTime.Parse(Value, CultureInfo.InvariantCulture); }
            catch { }

            bool positive = !(Value.Contains("-"));
            string tempValue = Value.Replace("-", "").Trim();
            bool date = UtilityHost.IsLike(tempValue, "D *");
            if (date)
                tempValue = tempValue.Substring(2);
            TimeSpan timeResult = new TimeSpan();

            foreach (string element in tempValue.Split(' '))
            {
                if (Regex.IsMatch(element, @"^\d+$"))
                    timeResult = timeResult.Add(new TimeSpan(0, 0, Int32.Parse(element)));
                else if (UtilityHost.IsLike(element, "*ms") && Regex.IsMatch(element, @"^\d+ms$", RegexOptions.IgnoreCase))
                    timeResult = timeResult.Add(new TimeSpan(0, 0, 0, 0, Int32.Parse(Regex.Match(element, @"^(\d+)ms$", RegexOptions.IgnoreCase).Groups[1].Value)));
                else if (UtilityHost.IsLike(element, "*s") && Regex.IsMatch(element, @"^\d+s$", RegexOptions.IgnoreCase))
                    timeResult = timeResult.Add(new TimeSpan(0, 0, Int32.Parse(Regex.Match(element, @"^(\d+)s$", RegexOptions.IgnoreCase).Groups[1].Value)));
                else if (UtilityHost.IsLike(element, "*m") && Regex.IsMatch(element, @"^\d+m$", RegexOptions.IgnoreCase))
                    timeResult = timeResult.Add(new TimeSpan(0, Int32.Parse(Regex.Match(element, @"^(\d+)m$", RegexOptions.IgnoreCase).Groups[1].Value), 0));
                else if (UtilityHost.IsLike(element, "*h") && Regex.IsMatch(element, @"^\d+h$", RegexOptions.IgnoreCase))
                    timeResult = timeResult.Add(new TimeSpan(Int32.Parse(Regex.Match(element, @"^(\d+)h$", RegexOptions.IgnoreCase).Groups[1].Value), 0, 0));
                else if (UtilityHost.IsLike(element, "*d") && Regex.IsMatch(element, @"^\d+d$", RegexOptions.IgnoreCase))
                    timeResult = timeResult.Add(new TimeSpan(Int32.Parse(Regex.Match(element, @"^(\d+)d$", RegexOptions.IgnoreCase).Groups[1].Value), 0, 0, 0));
                else
                    throw new ArgumentException(String.Format("Failed to parse as timespan: {0} at {1}", Value, element));
            }

            DateTime result;
            if (!positive)
                result = DateTime.Now.Add(timeResult.Negate());
            else
                result = DateTime.Now.Add(timeResult);

            if (date)
                return result.Date;
            return result;
        }
    }
}
