function New-DbaDbMasterKey {
    <#
    .SYNOPSIS
        Creates a database master key for encryption operations

    .DESCRIPTION
        Creates a database master key, which is required for implementing Transparent Data Encryption (TDE), Always Encrypted, or other database-level encryption features. The master key serves as the root encryption key that protects other encryption keys within the database. Defaults to creating the key in the master database if no specific database is specified, and will prompt securely for a password if none is provided.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Provides an alternative way to supply the master key password using a PSCredential object.
        Use this when you need to pass the password programmatically or when integrating with credential management systems. The password portion of the credential is used to encrypt the master key.

    .PARAMETER Database
        Specifies the database where the master key will be created. Defaults to master database if not specified.
        Use this when implementing encryption features like TDE or Always Encrypted in specific user databases rather than just the system master database.

    .PARAMETER SecurePassword
        Provides the password used to encrypt the database master key as a SecureString object.
        If not specified, you'll be prompted to enter the password securely via console. This password is required for SQL Server to decrypt the master key when the service starts.

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase.
        Use this when you want to create master keys across multiple databases in a single pipeline operation or when working with pre-filtered database collections.

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
        https://dbatools.io/New-DbaDbMasterKey

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.MasterKey

        Returns one MasterKey object for the database where the master key was created.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name where the master key was created
        - CreateDate: DateTime when the master key was created
        - DateLastModified: DateTime when the master key was last modified
        - IsEncryptedByServer: Boolean indicating if the master key is encrypted by the server

        Additional properties available (from SMO MasterKey object):
        - Urn: The Uniform Resource Name of the master key
        - State: Current state of the object (Existing, Creating, etc.)
        - Parent: Reference to parent database object

    .EXAMPLE
        PS C:\> New-DbaDbMasterKey -SqlInstance Server1

        You will be prompted to securely enter your password, then a master key will be created in the master database on server1 if it does not exist.


    .EXAMPLE
        PS C:\> New-DbaDbMasterKey -SqlInstance Server1 -Credential usernamedoesntmatter

        You will be prompted by a credential interface to securely enter your password, then a master key will be created in the master database on server1 if it does not exist.

    .EXAMPLE
        PS C:\> New-DbaDbMasterKey -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts to install but prompts in th console to securely enter your password and creates a master key in the 'db1' database

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$Database = "master",
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Credential) {
            $SecurePassword = $Credential.Password
        } else {
            if (-not $SecurePassword) {
                $SecurePassword = Read-Host "Password" -AsSecureString
            }
        }
    }
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database -ExcludeDatabase $ExcludeDatabase -SqlCredential $SqlCredential
        }

        foreach ($db in $InputObject) {
            if ($null -ne $db.MasterKey) {
                Stop-Function -Message "Master key already exists in the $($db.Name) database on $($db.Parent.Name)" -Target $db -Continue
            }

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating master key for database '$($db.Name)'")) {
                try {
                    $masterkey = New-Object Microsoft.SqlServer.Management.Smo.MasterKey $db
                    $masterkey.Create(($SecurePassword | ConvertFrom-SecurePass))

                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
                } catch {
                    Stop-Function -Message "Failed to create master key in $db on $instance" -Target $masterkey -ErrorRecord $_ -Continue
                }
            }
        }
    }
}