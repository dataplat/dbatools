using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Net;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Exceptions;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Parameter
{
    public partial class DbaInstanceParameter
    {
        /// <summary>
        /// Overrides the regular <c>ToString()</c> to show something pleasant and useful
        /// </summary>
        /// <returns>The <see cref="FullSmoName"/></returns>
        public override string ToString()
        {
            return FullSmoName;
        }
    }
}
