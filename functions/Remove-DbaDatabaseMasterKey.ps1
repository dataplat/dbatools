function Remove-DbaDatabaseMasterKey {
    <#
    .SYNOPSIS
        Deletes specified database master key

    .DESCRIPTION
        Deletes specified database master key.

    .PARAMETER SqlInstance
        The target SQL Server instance.

    .PARAMETER SqlCredential
        Allows you to login to SQL Server using alternative credentials.

    .PARAMETER Database
        The database where the master key will be removed.

    .PARAMETER ExcludeDatabase
        List of databases to exclude from clearing all master keys

    .PARAMETER All
        Purge the master keys from all databases on an instance.

    .PARAMETER MasterKeyCollection
        Internal parameter to support pipeline input

    .PARAMETER Mode
        Controls how the function handles cases where it can't do anything due to missing database or key:
        Strict: Write a warning (default)
        Lazy:   Write a verbose message
        Report: Create a report object as part of the output
        The default action can be adjusted by using Set-DbaConfig to change the 'message.mode.default' configuration

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .EXAMPLE
        Remove-DbaDatabaseMasterKey -SqlInstance Server1

        The master key in the master database on server1 will be removed if it exists.

    .EXAMPLE
        Remove-DbaDatabaseMasterKey -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts to remove the master key in the 'db1' database and drops the key.


    .NOTES
        Tags: Certificate

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT
#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ParameterSetName = "instanceExplicit")]
        [parameter(Mandatory, ParameterSetName = "instanceAll")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]
        $SqlInstance,

        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [parameter(Mandatory, ParameterSetName = "instanceExplicit")]
        [object[]]
        $Database,

        [parameter(ParameterSetName = "instanceAll")]
        [object[]]
        $ExcludeDatabase,

        [parameter(Mandatory, ParameterSetName = "instanceAll")]
        [switch]
        $All,

        [parameter(ValueFromPipeline, ParameterSetName = "collection")]
        [Microsoft.SqlServer.Management.Smo.MasterKey[]]
        $MasterKeyCollection,

        [DbaMode]
        $Mode = (Get-DbaConfigValue -Name 'message.mode.default' -Fallback "Strict"),

        [switch]
        [Alias('Silent')]$EnableException
    )

    begin {
        function Drop-Masterkey {
            [CmdletBinding()]
            Param (
                $masterkey,

                $mode = $Mode,

                $EnableException = $EnableException
            )
            $server = $masterkey.Parent.Parent
            $instance = $server.DomainInstanceName
            $cert = $masterkey.Name
            $db = $masterkey.Parent

            if ($Pscmdlet.ShouldProcess($instance, "Dropping the master key for database '$db'")) {
                try {
                    $masterkey.Drop()
                    Write-Message -Level Verbose -Message "Successfully removed master key from the $db database on $instance"

                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Status       = "Success"
                    }
                }
                catch {
                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Status       = "Failure"
                    }
                    Stop-Function -Message "Failed to drop master key from $db on $instance." -Target $db -InnerErrorRecord $_ -Continue
                }
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($All) {
                $Database = ($server.Databases | Where-Object Name -NotIn $ExcludeDatabase).Name
            }

            :Database foreach ($db in $Database) {
                $smodb = $server.Databases[$db]
                $masterkey = $smodb.MasterKey

                #region Case: Database Unknown
                if ($null -eq $smodb) {
                    switch ($Mode) {
                        [DbaMode]::Strict { Stop-Function -Message "Database '$db' does not exist on $instance" -Target $smodb -Continue -ContinueLabel database }
                        [DbaMode]::Lazy {
                            Write-Message -Level (Get-DbaConfigValue -Name 'message.mode.lazymessagelevel' -Fallback 4) -Message "Database '$db' does not exist on $instance" -Target $smodb
                            continue database
                        }
                        [DbaMode]::Report {
                            [pscustomobject]@{
                                ComputerName = $server.NetName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db
                                Status       = "Unknown Database"
                            }
                            continue Database
                        }
                    }
                }
                #endregion Case: Database Unknown

                #region Case: No Master Key
                if ($null -eq $masterkey) {
                    switch ($Mode.ToString()) {
                        "Strict" { Stop-Function -Message "No master key exists in the $db database on $instance" -Target $smodb -Continue -ContinueLabel database }
                        "Lazy" {
                            Write-Message -Level (Get-DbaConfigValue -Name 'message.mode.lazymessagelevel' -Fallback 4) -Message "No master key exists in the $db database on $instance" -Target $smodb
                            continue database
                        }
                        "Report" {
                            [pscustomobject]@{
                                ComputerName = $server.NetName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $smodb.Name
                                Status       = "No Masterkey"
                            }
                            continue Database
                        }
                    }
                }
                #endregion Case: No Master Key

                Write-Message -Level Verbose -Message "Removing master key from $db"
                Drop-Masterkey -masterkey $masterkey
            }
        }

        foreach ($key in $MasterKeyCollection) {
            Write-Message -Level Verbose -Message "Removing master key: $key"
            Drop-Masterkey -masterkey $key
        }
    }
}