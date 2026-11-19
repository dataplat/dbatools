using System;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Utility
{
    public partial class DbaTimeSpan
    {
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
    }
}
