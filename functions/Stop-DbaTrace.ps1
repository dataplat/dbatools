function Stop-DbaTrace {
     <#
        .SYNOPSIS
        Stop a list of trace(s) from specified SQL Server Instance

        .DESCRIPTION
        This command stops a trace on a SQL Server Instance

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
        License: MIT https://opensource.org/licenses/MIT

       .EXAMPLE
        Stop-DbaTrace -SqlInstance sql2008

        Stops all traces on sql2008
    
        .EXAMPLE
        Stop-DbaTrace -SqlInstance sql2008 -Id 1

        Stops all trace with ID 1 on sql2008
    
        .EXAMPLE
        Get-DbaTrace -SqlInstance sql2008 | Out-GridView -PassThru | Stop-DbaTrace

        Stops selected traces on sql2008

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
                Stop-Function -Message "The default trace on $server cannot be stopped. Use Set-DbaSpConfigure to turn it off." -Continue
            }
            
            $sql = "sp_trace_setstatus $traceid, 0"
            
            try {
                $server.Query($sql)
                $output = Get-DbaTrace -SqlInstance $server -Id $traceid
                if (-not $output) {
                    $output = [PSCustomObject]@{
                        ComputerName            = $server.NetName
                        InstanceName            = $server.ServiceName
                        SqlInstance             = $server.DomainInstanceName
                        Id                      = $traceid
                        Status                  = $null
                        IsRunning               = $false
                        Path                    = $null
                        MaxSize                 = $null
                        StopTime                = $null
                        MaxFiles                = $null
                        IsRowset                = $null
                        IsRollover              = $null
                        IsShutdown              = $null
                        IsDefault               = $null
                        BufferCount             = $null
                        BufferSize              = $null
                        FilePosition            = $null
                        ReaderSpid              = $null
                        StartTime               = $null
                        LastEventTime           = $null
                        EventCount              = $null
                        DroppedEventCount       = $null
                        Parent                  = $server
                    } | Select-DefaultView -Property 'ComputerName', 'InstanceName', 'SqlInstance', 'Id', 'IsRunning'
                }
                $output
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                return
            }
        }
    }
}