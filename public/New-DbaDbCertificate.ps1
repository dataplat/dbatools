function New-DbaDbCertificate {
    <#
    .SYNOPSIS
        Creates a new database certificate for encryption and security purposes

    .DESCRIPTION
        Creates a new database certificate within a specified database using SQL Server Management Objects. Database certificates are essential for implementing Transparent Data Encryption (TDE), encrypting stored procedures and functions, securing Service Broker dialogs, and enabling column-level encryption. The certificate can be password-protected or secured by the database master key, with configurable expiration dates and subject information. If no database is specified, the certificate will be created in the master database.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where the certificate will be created. Defaults to master.

    .PARAMETER Name
        Optional name to create the certificate. Defaults to database name.

    .PARAMETER Subject
        Optional subject that will be used when creating all certificates

    .PARAMETER StartDate
        Optional start date that will be used when creating all certificates

        By default, certs will start immediately

    .PARAMETER ExpirationDate
        Optional expiration that will be used when creating all certificates

        By default, certs will last 5 years

    .PARAMETER ActiveForServiceBrokerDialog
        Microsoft has not provided a description so we can only assume the cert is active for service broker dialog

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
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbCertificate

    .EXAMPLE
        PS C:\> New-DbaDbCertificate -SqlInstance Server1

        You will be prompted to securely enter your password, then a certificate will be created in the master database on server1 if it does not exist.

    .EXAMPLE
        PS C:\> New-DbaDbCertificate -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts to install but prompts to securely enter your password and creates a certificate in the 'db1' database

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$Database = "master",
        [string[]]$Subject,
        [datetime]$StartDate = (Get-Date),
        [datetime]$ExpirationDate = $StartDate.AddYears(5),
        [switch]$ActiveForServiceBrokerDialog,
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $db.Name
                Write-Message -Level Verbose -Message "Name of certificate not specified, setting it to '$name'"
            }

            if ((Test-Bound -Not -ParameterName Subject)) {
                Write-Message -Level Verbose -Message "Subject not specified, setting it to '$Name Database Certificate'"
                $subject = "$Name Database Certificate"
            }

            foreach ($cert in $Name) {
                $null = $db.Certificates.Refresh()
                if ($null -ne $db.Certificates[$cert]) {
                    Stop-Function -Message "Certificate '$cert' already exists in $($db.Name) on $($db.Parent.Name)" -Target $db -Continue
                }

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating certificate for database '$($db.Name)'")) {

                    # something is up with .net, force a stop
                    $eap = $ErrorActionPreference
                    $ErrorActionPreference = 'Stop'
                    try {
                        $smocert = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Certificate $db, $cert
                        $smocert.StartDate = $StartDate
                        $smocert.Subject = $Subject
                        $smocert.ExpirationDate = $ExpirationDate
                        $smocert.ActiveForServiceBrokerDialog = $ActiveForServiceBrokerDialog

                        if ($SecurePassword) {
                            Write-Message -Level Verbose -Message "Creating certificate with password"
                            $smocert.Create(($SecurePassword | ConvertFrom-SecurePass))
                        } else {
                            Write-Message -Level Verbose -Message "Creating certificate without password, so it'll be protected by the master key"
                            $smocert.Create()
                        }

                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name Credential -value $Credential
                        Select-DefaultView -InputObject $smocert -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
                    } catch {
                        $ErrorActionPreference = $eap
                        Stop-Function -Message "Failed to create certificate in $($db.Name) on $($db.Parent.Name)" -Target $smocert -ErrorRecord $_ -Continue
                    }
                    $ErrorActionPreference = $eap
                }
            }
        }
    }
}