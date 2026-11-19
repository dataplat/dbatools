using System;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Utility
{
    public partial class DbaDateTimeBase
    {
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
    }
}
