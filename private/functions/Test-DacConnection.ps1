function Test-DacConnection {
    <#
    .SYNOPSIS
        Internal function.

    .DESCRIPTION
        Tests whether a connection that was passed in is already a dedicated admin connection (DAC).

        SQL Server only allows one DAC per instance, so commands that need a DAC to decrypt passwords
        have to reuse an existing one instead of opening a second one. Connect-DbaInstance prefixes the
        server name with "ADMIN:" when -DedicatedAdminConnection is used, so that prefix is what marks
        a connection as a DAC.

        This function is used by the following public functions:
        - Copy-DbaCredential
        - Copy-DbaDbMail
        - Copy-DbaLinkedServer
        - Export-DbaCredential
        - Export-DbaInstance
        - Export-DbaLinkedServer
        - Invoke-DbaDbDecryptObject
        - Start-DbaMigration
        - Sync-DbaAvailabilityGroup

    .PARAMETER InputObject
        The connection to test. Accepts a DbaInstanceParameter (as used by the SqlInstance and Source
        parameters of the public commands) or an SMO server object. Anything that is not a connection
        to an already connected instance returns $false.

    .NOTES
        Tags: Connection, DAC
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Test-DacConnection -InputObject $Source

        Returns $true if $Source is a server object that is connected via a dedicated admin connection.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $false
    }

    if ($InputObject.GetType().FullName -eq "Dataplat.Dbatools.Parameter.DbaInstanceParameter") {
        # Only a DbaInstanceParameter of type Server holds an already connected server object
        if ($InputObject.Type -ne "Server") {
            return $false
        }
        $server = $InputObject.InputObject
    } else {
        $server = $InputObject
    }

    # Depending on how the connection was built, the "ADMIN:" prefix is visible on the server object, on the connection context, or both
    return [bool]($server.Name -match "^ADMIN:" -or $server.ConnectionContext.ServerInstance -match "^ADMIN:")
}
