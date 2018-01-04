function New-DbaServiceMasterKey {
    <#
.SYNOPSIS
Creates a new service master key

.DESCRIPTION
Creates a new service master key in the master database

.PARAMETER SqlInstance
The target SQL Server instances

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

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
New-DbaServiceMasterKey -SqlInstance Server1

You will be prompted to securely enter your Service Key Password twice, then a master key will be created in the master database on server1 if it does not exist.

#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Security.SecureString]$Password,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            if (Test-Bound -ParameterName Password -Not) {
                $password = Read-Host -AsSecureString -Prompt "You must enter Service Key password for $instance"
                $password2 = Read-Host -AsSecureString -Prompt "Type the password again"

                if (([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password))) -ne ([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password2)))) {
                    Stop-Function -Message "Passwords do not match" -Continue
                }
            }
            New-DbaDatabaseMasterKey -SqlInstance $instance -Database master -Password $password
        }
    }
}