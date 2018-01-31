function Start-DbaTrace {
     <#
        .SYNOPSIS
        Start a list of trace(s) from specified SQL Server Instance

        .DESCRIPTION
        This command starts a trace on a SQL Server Instance

        .PARAMETER SqlInstance
        A SQL Server instance to connect to

        .PARAMETER SqlCredential
        A credential to use to connect to the SQL Instance rather than using Windows Authentication

        .PARAMETER Id
        A list of trace ids
    
        .PARAMETER InputObject
        Internal parameter for piping
    
        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
        Tags: Security, Trace
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

       .EXAMPLE
        Start-DbaTrace -SqlInstance sql2008

        Starts all traces on sql2008
    
        .EXAMPLE
        Start-DbaTrace -SqlInstance sql2008 -Id 1

        Starts all trace with ID 1 on sql2008
    
        .EXAMPLE
        Get-DbaTrace -SqlInstance sql2008 | Out-GridView -PassThru | Start-DbaTrace

        Starts selected traces on sql2008

#>
    [CmdletBinding()]
    Param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int[]]$Id,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and $SqlInstance) {
            $InputObject = Get-DbaTrace -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Id $Id
        }
        
        foreach ($trace in $InputObject) {
            if (-not $trace.id -and -not $trace.Parent) {
                Stop-Function -Message "Input is of the wrong type. Use Get-DbaTrace." -Continue
                return
            }
            
            $server = $trace.Parent
            $traceid = $trace.id
            $default = Get-DbaTrace -SqlInstance $server -Default
            
            if ($default.id -eq $traceid) {
                Stop-Function -Message "The default trace on $server cannot be started. Use Set-DbaSpConfigure to turn it on." -Continue
            }
            
            $sql = "sp_trace_setstatus $traceid, 1"
            
            try {
                $server.Query($sql)
                Get-DbaTrace -SqlInstance $server -Id $traceid
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                return
            }
        }
    }
}