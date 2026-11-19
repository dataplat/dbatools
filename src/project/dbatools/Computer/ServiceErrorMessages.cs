namespace Dataplat.Dbatools.Computer
{
    /// <summary>
    /// Native value lookup for private/functions/Get-DbaServiceErrorMessage.ps1.
    /// This utility does not implement the PowerShell function's parameter binding
    /// or end-block pipeline behavior. Zero returns the complete message table.
    /// </summary>
    public static class ServiceErrorMessages
    {
        private static readonly string[] Messages =
        {
            "The request was accepted.",
            "The request is not supported.",
            "The user did not have the necessary access.",
            "The service cannot be stopped because other services that are running are dependent on it.",
            "The requested control code is not valid, or it is unacceptable to the service.",
            "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2.",
            "The service has not been started.",
            "The service did not respond to the start request in a timely fashion.",
            "Unknown failure when starting the service.",
            "The directory path to the service executable file was not found.",
            "The service is already running.",
            "The database to add a new service is locked.",
            "A dependency this service relies on has been removed from the system.",
            "The service failed to find the service needed from a dependent service.",
            "The service has been disabled from the system.",
            "The service does not have the correct authentication to run on the system.",
            "This service is being removed from the system.",
            "The service has no execution thread.",
            "The service has circular dependencies when it starts.",
            "A service is running under the same name.",
            "The service name has invalid characters.",
            "Invalid parameters have been passed to the service.",
            "The account under which this service runs is either invalid or lacks the permissions to run the service.",
            "The service exists in the database of services available from the system.",
            "The service is currently paused in the system.",
        };

        /// <summary>
        /// Returns a caller-owned array containing the selected message, or all
        /// messages for zero (the private helper's omitted-argument behavior).
        /// Values outside the table return the pinned unknown-error text.
        /// </summary>
        public static string[] Resolve(int errorNumber = 0)
        {
            if (errorNumber == 0)
                return (string[])Messages.Clone();
            if (errorNumber > 0 && errorNumber < Messages.Length)
                return new[] { Messages[errorNumber] };
            return new[] { "Unknown error." };
        }
    }
}
