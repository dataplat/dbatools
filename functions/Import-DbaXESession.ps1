function Import-DbaXESessionTemplate {
 <#
    .SYNOPSIS
    Imports a new XESession XML Template

    .DESCRIPTION
    Imports a new XESession XML Template either from our repo or a file you specify

    .PARAMETER SqlInstance
    The SQL Instances that you're connecting to.

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user

    .PARAMETER Name
    The Name of the session

    .PARAMETER Path
    The path to the xml file or files

    .PARAMETER Template
    From one of the templates we curated for you (tab through -Template to see options)

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Import-DbaXESessionTemplate

    .EXAMPLE
    Import-DbaXESessionTemplate -SqlInstance sql2017 -Template db_query_wait_stats

    Creates a new XESession named db_query_wait_stats from our repo to the SQL Server sql2017

    .EXAMPLE
    Import-DbaXESessionTemplate -SqlInstance sql2017 -Template db_query_wait_stats -Name "Query Wait Stats"

    Creates a new XESession named "Query Wait Stats" using the db_query_wait_stats template

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Name,
        [string[]]$Path,
        [string[]]$Template,
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -ParameterName Path -Not) -and (Test-Bound -ParameterName Template -Not)) {
            Stop-Function -Message "You must specify Path or Template"
        }

        if (($Path.Count -gt 1 -or $Tempalte.Count -gt 1) -and (Test-Bound -ParameterName Template)) {
            Stop-Function -Message "Name cannot be specified with multiple files or templates because the Session will already exist"
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $SqlConn = $server.ConnectionContext.SqlConnectionObject
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $store = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection

            foreach ($file in $path) {
                try {
                    $xml = [xml](Get-Content $file -ErrorAction Stop)
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                }

                if (-not $xml.event_sessions) {
                    Stop-Function -Message "$file is not a valid XESession tempalte document" -Continue
                }
                try {
                    if ((Test-Bound -ParameterName Name -not)) {
                        $Name = (Get-ChildItem $file).BaseItem
                    }

                    $store.CreateSessionFromTemplate($Name, $file)
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue
                }
            }

            foreach ($file in $template) {
                $templatepath = "$script:PSModuleRoot\bin\xetemplates\$file.xml"
                if ((Test-Path $TempaltePath)) {
                    try {
                        if ((Test-Bound -ParameterName Name -not)) {
                            $Name = $file
                        }
                        $store.CreateSessionFromTemplate($Name, $Template)
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue
                    }
                }
                else {
                    Stop-Function -Message "Invalid template ($templatepath does not exist)" -Continue
                }
            }
        }
    }
}