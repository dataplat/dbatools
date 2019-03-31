function Set-DbaStartupProcedure {
    <#
    .SYNOPSIS
        Returns the uptime of the SQL Server instance, and if required the hosting windows server

    .DESCRIPTION
        By default, this command returns for each SQL Server instance passed in:
        SQL Instance last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
        Hosting Windows server last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

        Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

        To connect to SQL Server as a different Windows user, run PowerShell as that user.

    .PARAMETER StartupProcedure
        The Procedure(s) to process.

    .PARAMETER Disable
        If this switch is enabled, listed procedures will be disabled.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Procedure, Startup, StartupProcedure
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaStartupProcedure

    .EXAMPLE
        PS C:\> Set-DbaStartupProcedure -SqlInstance SqlBox1\Instance2 -StartupProcedure '[dbo].[StartUpProc1]'

        Attempts to set the procedure '[dbo].[StartUpProc1]' in the master database of SqlBox1\Instance2 for automatic execution when the instance is started.

    .EXAMPLE
        PS C:\> Set-DbaStartupProcedure -SqlInstance winserver\sqlexpress, sql2016 -StartupProcedure '[dbo].[StartUpProc1]' -Disable

        Attempts to clear the automatic execution of the procedure '[dbo].[StartUpProc1]' in the master database of the sqlexpress instance on host winserver  and the default instance on host sql2016 when the instance is started.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$StartupProcedure,
        [switch]$Disable,
        [switch]$EnableException
    )
    begin {
        if ($Disable -eq $false) {
            $action = 'Enable'
            $startup = $true
        } else {
            $action = 'Disable'
            $startup = $false
        }
        function Get-ObjectParts {
            <#
            .SYNOPSIS
                Parse a one or two part object name into seperate paths

            .EXAMPLE
                Get-ObjectParts 'ProcName'

                Parses a two-part name into its constitute parts.

            .EXAMPLE
            Get-ObjectParts '[Schema.With.Dots]]].[Another .Silly]] Name..]'

                Parses a two-part name into its constitute parts. Uses square brackets to enclose special characters.
            #>
            param (
                [string]$ObjectName
            )
            process {
                $fqtns = @()
                #Objects with a ']' charcter in name need to be handeled
                #Require charcter to be escaped by being duplicated as per T-SQL QuoteName function
                #These need to be temporarily replaced to allow name to be parsed.
                $t = $ObjectName
                if ($t.Contains(']]')) {
                    for ($i = 0; $i -le 65535; $i++) {
                        $hexStr = '{0:X4}' -f $i
                        $char = [regex]::Unescape("\u$($HexStr)")
                        if (!$ObjectName.Contains($Char)) {
                            $fixChar = $Char
                            $t = $t.Replace(']]', $fixChar)
                            Break
                        }
                    }
                } else {
                    $fixChar = $null
                }

                Write-Message -Level Verbose -Message "Splitting parts for $t"
                $splitName = [regex]::Matches($t, "(\[.+?\])|([^\.]+)").Value
                $dotcount = $splitName.Count
                Write-Message -Level Debug -Message "Parts: $dotcount"

                $schema = $proc = $null

                switch ($dotcount) {
                    1 {
                        $schema = 'dbo'
                        $proc = $t
                        $parsed = $true
                    }
                    2 {
                        $schema = $splitName[0]
                        $proc = $splitName[1]
                        $parsed = $true
                    }
                    default {
                        $parsed = $false
                    }
                }

                Write-Message -Level Debug -Message "Schema: $schema"
                if ($schema -like "[[]*[]]") {
                    $schema = $schema.Substring(1, ($schema.Length - 2))
                    if ($fixChar) {
                        $schema = $schema.Replace($fixChar, ']')
                    }
                }

                Write-Message -Level Debug -Message "Proc: $proc"
                if ($proc -like "[[]*[]]") {
                    $proc = $proc.Substring(1, ($proc.Length - 2))
                    if ($fixChar) {
                        $proc = $proc.Replace($fixChar, ']')
                    }
                }
                $fqtns = [PSCustomObject] @{
                    InputValue = $ObjectName
                    Schema     = $schema
                    ProcName   = $proc
                    Parsed     = $parsed
                }
                return $fqtns
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
            }
            Write-Message -Level Verbose -Message "Getting startup procedures for $instance"

            $db = $server.Databases['master']

            foreach ($proc in $StartupProcedure) {
                Write-Message -Level Verbose -Message "Preparing to get object parts for $proc"
                $procParts = Get-ObjectParts $proc

                if ($procParts.Parsed) {
                    $sp = $db.StoredProcedures.Item($procParts.ProcName, $procParts.Schema)

                    if ($null -eq $sp) {
                        $status = $false
                        $note = "Requested procedure does not exist"
                    } else {
                        try {
                            if ($sp.Startup -eq $startup) {
                                $status = $true
                                $note = "Requested status already set."

                            } else {
                                if ($Pscmdlet.ShouldProcess("$instance", "Setting Startup status of $proc to $startup")) {
                                    $sp.Startup = $startup
                                    $sp.Alter()
                                    $status = $true
                                    $note = "$action succeded"
                                } else {
                                    $status = $false
                                    $note = "$action skipped"
                                }
                            }

                        } catch {
                            $status = $false
                            $note = "$action failed"
                        }
                    }

                } else {
                    $status = $false
                    $note = "Unable to split procedure"
                }

                [PSCustomObject]@{
                    ComputerName     = $server.ComputerName
                    SqlInstance      = $server.DomainInstanceName
                    InstanceName     = $server.ServiceName
                    StartupProcedure = $proc
                    Action           = $action
                    Status           = $status
                    Note             = $note
                }
            }
        }
    }
}