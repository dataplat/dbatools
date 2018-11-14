function Get-DbaServiceErrorMessage {
    <#
    .SYNOPSIS
    Internal function. Returns the list of error code messages for Windows service management.

    #>
    param(
        [parameter(ValueFromPipeline, Position = 1)]
        [int]$ErrorNumber
    )
    $returnCodes = @("The request was accepted.",
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
        "The service is currently paused in the system.")
    if ($ErrorNumber) {
        if ($ErrorNumber -in 0..($returnCodes.Length - 1)) { Return $returnCodes[$ErrorNumber] }
        else { Return "Unknown error." }
    } else {
        $returnCodes
    }
}