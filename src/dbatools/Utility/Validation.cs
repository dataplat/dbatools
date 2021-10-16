using System;

namespace Sqlcollaborative.Dbatools.Utility
{
    using System.Net;
    using System.Net.NetworkInformation;
    using System.Text.RegularExpressions;
    /// <summary>
    /// Provides helper methods that aid in validating stuff.
    /// </summary>
    public static class Validation
    {
        /// <summary>
        /// Tests whether a given string is the local host.
        /// Does NOT use DNS resolution, DNS aliases will NOT be recognized!
        /// </summary>
        /// <param name="Name">The name to test for being local host</param>
        /// <returns>Whether the name is localhost</returns>
        public static bool IsLocalhost(string Name)
        {
            #region Handle IP Addresses
            try
            {
                IPAddress tempAddress;
                IPAddress.TryParse(Name, out tempAddress);
                if (IPAddress.IsLoopback(tempAddress))
                    return true;

                foreach (NetworkInterface netInterface in NetworkInterface.GetAllNetworkInterfaces())
                {
                    IPInterfaceProperties ipProps = netInterface.GetIPProperties();
                    foreach (UnicastIPAddressInformation addr in ipProps.UnicastAddresses)
                    {
                        if (tempAddress.ToString() == addr.Address.ToString())
                            return true;
                    }
                }
            }
            catch { }
            #endregion Handle IP Addresses

            #region Handle Names
            try
            {
                if (Name == ".")
                    return true;
                if (Name.ToLower() == "localhost")
                    return true;
                if (Name.ToLower() == Environment.MachineName.ToLower())
                    return true;
                if (Name.ToLower() == (Environment.MachineName + "." + Environment.GetEnvironmentVariable("USERDNSDOMAIN")).ToLower())
                    return true;
            }
            catch { }
            #endregion Handle Names
            return false;
        }

        /// <summary>
        /// Tests whether a given string is a recommended instance name. Recommended names musst be legal, nbot on the ODBC list and not on the list of words likely to become reserved keywords in the future.
        /// </summary>
        /// <param name="InstanceName">The name to test. MAY contain server name, but will NOT test the server.</param>
        /// <returns>Whether the name is recommended</returns>
        public static bool IsRecommendedInstanceName(string InstanceName)
        {
            string temp;
            if (InstanceName.Split('\\').Length == 1) { temp = InstanceName; }
            else if (InstanceName.Split('\\').Length == 2) { temp = InstanceName.Split('\\')[1]; }
            else { return false; }

            if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeyword, RegexOptions.IgnoreCase)) { return false; }
            if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeywordFuture, RegexOptions.IgnoreCase)) { return false; }
            if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeywordOdbc, RegexOptions.IgnoreCase)) { return false; }

            if (temp.ToLower() == "default") { return false; }
            if (temp.ToLower() == "mssqlserver") { return false; }

            if (!Regex.IsMatch(temp, RegexHelper.InstanceName, RegexOptions.IgnoreCase)) { return false; }

            return true;
        }

        /// <summary>
        /// Tests whether a given string is a valid target for targeting as a computer. Will first convert from idn name.
        /// </summary>
        public static bool IsValidComputerTarget(string ComputerName)
        {
            try
            {
                System.Globalization.IdnMapping mapping = new System.Globalization.IdnMapping();
                string temp = mapping.GetAscii(ComputerName);
                return Regex.IsMatch(temp, RegexHelper.ComputerTarget);
            }
            catch { return false; }
        }

        /// <summary>
        /// Tests whether a given string is a valid instance name.
        /// </summary>
        /// <param name="InstanceName">The name to test. MAY contain server name, but will NOT test the server.</param>
        /// <param name="Lenient">Setting this to true will make the validation ignore default and mssqlserver as illegal names (as they are illegal names for named instances, but legal for targeting)</param>
        /// <returns>Whether the name is legal</returns>
        public static bool IsValidInstanceName(string InstanceName, bool Lenient = false)
        {
            string temp;
            if (InstanceName.Split('\\').Length == 1) { temp = InstanceName; }
            else if (InstanceName.Split('\\').Length == 2) { temp = InstanceName.Split('\\')[1]; }
            else { return false; }

            if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeyword, RegexOptions.IgnoreCase)) { return false; }

            if (!Lenient)
            {
                if (temp.ToLower() == "default") { return false; }
                if (temp.ToLower() == "mssqlserver") { return false; }
            }

            if (!Regex.IsMatch(temp, RegexHelper.InstanceName, RegexOptions.IgnoreCase)) { return false; }

            return true;
        }
    }
}