using System;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// The distinct failure classes of public/Connect-DbaInstance.ps1, so the cmdlet can map
    /// each one back to the exact Stop-Function call site (message, category, continue-vs-stop)
    /// of the PS source.
    /// </summary>
    public enum ConnectionResolutionFailure
    {
        /// <summary>The verify query (and any sanctioned retry) failed. PS: Stop-Function -Message "Failure" -Category ConnectionError -Continue.</summary>
        ConnectFailure = 0,

        /// <summary>-AzureUnsupported was set and the target is Azure SQL Database. PS: Stop-Function -Message "Azure SQL Database not supported" -Continue.</summary>
        AzureUnsupported = 1,

        /// <summary>The target is below -MinimumVersion. PS: Stop-Function -Message "SQL Server version N required - X not supported." -Continue.</summary>
        MinimumVersion = 2,

        /// <summary>Windows credentials on a non-Windows host. PS: Stop-Function (no -Continue) followed by return, aborting the remaining instances.</summary>
        WindowsCredentialOnUnix = 3,

        /// <summary>A SecureString access token could not be converted. PS: Stop-Function -Continue.</summary>
        AccessTokenConversion = 4,

        /// <summary>The target is older than SQL Server 2008 (dbatools PR 10813). PS: Stop-Function -Message "X runs SQL Server 2005, which dbatools no longer supports: ..." -Continue.</summary>
        UnsupportedVersion = 5,

        /// <summary>
        /// A passed-in server's copied context needs a new connection its connection string cannot log in with
        /// (pinned 962-980). PS: Stop-Function -Message "Cannot apply the requested settings to ..." or "Cannot change the
        /// database of ..." -Target $instance -Continue.
        /// </summary>
        CopiedContextRefused = 6
    }

    /// <summary>
    /// Thrown by ConnectionService.ResolveInstance when a resolution fails. Message text is
    /// composed verbatim to the PS Stop-Function message of the corresponding call site;
    /// InnerException carries the original failure for the -ErrorRecord parity of the
    /// ConnectFailure site.
    /// </summary>
    public class ConnectionResolutionException : Exception
    {
        /// <summary>Which PS Stop-Function call site this failure corresponds to.</summary>
        public ConnectionResolutionFailure Kind { get; private set; }

        /// <summary>Creates the exception.</summary>
        /// <param name="kind">The failure class</param>
        /// <param name="message">The verbatim PS Stop-Function message</param>
        /// <param name="innerException">The original failure, when one was caught</param>
        public ConnectionResolutionException(ConnectionResolutionFailure kind, string message, Exception innerException)
            : base(message, innerException)
        {
            Kind = kind;
        }
    }
}
