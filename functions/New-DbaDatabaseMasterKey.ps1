function New-DbaDatabaseMasterKey {
    <#
.SYNOPSIS
Creates a new database master key

.DESCRIPTION
Creates a new database master key. If no database is specified, the master key will be created in master.

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the master key will be created. Defaults to master.

.PARAMETER Password
Secure string used to create the key.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
New-DbaDatabaseMasterKey -SqlInstance Server1

You will be prompted to securely enter your password, then a master key will be created in the master database on server1 if it does not exist.

.EXAMPLE
New-DbaDatabaseMasterKey -SqlInstance Server1 -Database db1 -Confirm:$false

Suppresses all prompts to install but prompts to securely enter your password and creates a master key in the 'db1' database


#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database = "master",
        [parameter(Mandatory)]
        [Security.SecureString]$Password = (Read-Host "Password" -AsSecureString),
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($db in $Database) {
                $smodb = $server.Databases[$db]

                if ($null -eq $smodb) {
                    Stop-Function -Message "Database '$db' does not exist on $instance" -Target $smodb -Continue
                }

                if ($null -ne $smodb.MasterKey) {
                    Stop-Function -Message "Master key already exists in the $db database on $instance" -Target $smodb -Continue
                }

                if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating master key for database '$db' on $instance")) {
                    try {
                        $masterkey = New-Object Microsoft.SqlServer.Management.Smo.MasterKey $smodb
                        $masterkey.Create(([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password))))

                        Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.NetName
                        Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $smodb

                        Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
                    }
                    catch {
                        Stop-Function -Message "Failed to create master key in $db on $instance. Exception: $($_.Exception.InnerException)" -Target $masterkey -InnerErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}