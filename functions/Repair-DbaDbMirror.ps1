#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Repair-DbaDbMirror {
    <#
        .SYNOPSIS
            Attempts to repair a suspended or paused mirroring database.

        .DESCRIPTION
            Attempts to repair a suspended mirroring database.
    
            Restarts the endpoints then sets the partner to resume. See this article for more info:
    
            http://www.sqlservercentral.com/blogs/vivekssqlnotes/2016/09/03/how-to-resume-suspended-database-mirroring-in-sql-server-/

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
    
        .PARAMETER Database
            The target database.
    
        .PARAMETER InputObject
            Allows piping from Get-DbaDatabase.
    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Mirror, HA
            Author: Chrissy LeMaire (@cl), netnerds.net
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Repair-DbaDbMirror

        .EXAMPLE
            PS C:\> Repair-DbaDbMirror -SqlInstance localhost

            Returns all Endpoint(s) on the local default SQL Server instance

        .EXAMPLE
            PS C:\> Repair-DbaDbMirror -SqlInstance localhost, sql2016

            Returns all Endpoint(s) for the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }
        
        foreach ($db in $InputObject) {
            try {
                Get-DbaEndpoint -SqlInstance $db.Parent | Where-Object EndpointType -eq DatabaseMirroring | Stop-DbaEndPoint
                Get-DbaEndpoint -SqlInstance $db.Parent | Where-Object EndpointType -eq DatabaseMirroring | Start-DbaEndPoint
                $db | Set-DbaDbMirror -State Resume
                $db
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}