function New-DbaDbAsymmetricKey {
    <#
    .SYNOPSIS
        Creates a new database asymmetric key

    .DESCRIPTION
        Creates a new database asymmetric key. If no database is specified, the asymmetric key will be created in master.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where the asymmetric key will be created. Defaults to master.

    .PARAMETER Name
        Optional name to create the asymmetric key. Defaults to database name.

    .PARAMETER SecurePassword
        Optional password - if no password is supplied, the password will be protected by the master key

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: asymmetrickey
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetricKey -SqlInstance Server1

        You will be prompted to securely enter your password, then an asymmetric key will be created in the master database on server1 if it does not exist.

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts to install but prompts to securely enter your password and creates an asymmetric key in the 'db1' database

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$Database = "master",
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [String]$Owner,
        [String]$FilePath,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [ValidateSet('Rsa4096', 'Rsa3072', 'Rsa2048', 'Rsa1024', 'Rsa512')]
        [string]$Algorithm = 'Rsa2048',
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ((Test-Bound -Not -ParameterName Name)) {
                Write-Message -Level Verbose -Message "Name of asymmetric key not specified, setting it to '$db'"
                $Name = $db.Name
            }

            foreach ($askey in $Name) {
                if ($null -ne $db.AsymmetricKeys[$askey]) {
                    Stop-Function -Message "Asymmetric Key '$askey' already exists in $($db.Name) on $($db.Parent.Name)" -Target $db -Continue
                }

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating asymmetric key for database '$($db.Name)'")) {

                    # something is up with .net, force a stop
                    $eap = $ErrorActionPreference
                    $ErrorActionPreference = 'Stop'
                    try {
                        $smokey = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AsymmetricKey $db, $askey
                        $smokey = $Name

                        if ($SecurePassword) {
                            $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm, ([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword))))
                        } else {
                            $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm)
                        }

                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Credential -value $Credential
                        Select-DefaultView -InputObject $smokey -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
                    } catch {
                        $ErrorActionPreference = $eap
                        Stop-Function -Message "Failed to create asymmetric key in $($db.Name) on $($db.Parent.Name)" -Target $smocert -ErrorRecord $_ -Continue
                    }
                    $ErrorActionPreference = $eap
                }
            }
        }
    }
}