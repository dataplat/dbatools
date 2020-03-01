function New-DbaCredential {
    <#
    .SYNOPSIS
        Creates a new SQL Server credential

    .DESCRIPTION
        Creates a new credential

    .PARAMETER SqlInstance
        The target SQL Server(s)

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The Credential name

    .PARAMETER Identity
        The Credential Identity

    .PARAMETER SecurePassword
        Secure string used to authenticate the Credential Identity

    .PARAMETER MappedClassType
        Sets the class associated with the credential.

    .PARAMETER ProviderName
        Sets the name of the provider

    .PARAMETER Force
        If credential exists, drop and recreate

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Credential
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaCredential

    .EXAMPLE
        PS C:\> New-DbaCredential -SqlInstance Server1

        You will be prompted to securely enter your password, then a credential will be created in the master database on server1 if it does not exist.

    .EXAMPLE
        PS C:\> New-DbaCredential -SqlInstance Server1 -Confirm:$false

        Suppresses all prompts to install but prompts to securely enter your password and creates a credential on Server1.

    .EXAMPLE
        PS C:\> $params = @{
        >>SqlInstance = "Server1"
        >>Name = "AzureBackupBlobStore"
        >>Identity = "https://<Azure Storage Account Name>.blob.core.windows.net/<Blob Container Name>"
        >>SecurePassword = (ConvertTo-SecureString '<Azure Storage Account Access Key>' -AsPlainText -Force)
        >>}
        PS C:\> New-DbaCredential @params

        Creates a credential, "AzureBackupBlobStore", on Server1 using the Access Keys for Backup To URL. Identity must be the full URI for the blob container that will be the backup target. The SecurePassword supplied is one of the two Access Keys for the Azure Storage Account.

    .EXAMPLE
        PS C:\> $sasParams = @{
        >>SqlInstance = "server1"
        >>Name = "https://<azure storage account name>.blob.core.windows.net/<blob container>"
        >>Identity = "SHARED ACCESS SIGNATURE"
        >>SecurePassword = (ConvertTo-SecureString '<Shared Access Token>' -AsPlainText -Force)
        >>}
        PS C:\> New-DbaCredential @sasParams

        Create a credential on Server1 using a SAS token for Backup To URL. The Name is the full URI for the blob container that will be the backup target.
        The SecurePassword will be the Shared Access Token (SAS), as a SecureString.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Name = $Identity,
        [parameter(Mandatory)]
        [Alias("CredentialIdentity")]
        [string[]]$Identity,
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [ValidateSet('CryptographicProvider', 'None')]
        [string]$MappedClassType = "None",
        [string]$ProviderName,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $mappedClass = switch ($MappedClassType) {
            "CryptographicProvider" { 1 }
            "None" { 0 }
        }
    }

    process {
        if (!$SecurePassword) {
            Read-Host -AsSecureString -Prompt "Enter the credential password"
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($cred in $Identity) {
                $currentCred = $server.Credentials[$Name]

                if ($currentCred) {
                    if ($force) {
                        Write-Message -Level Verbose -Message "Dropping credential $Name"
                        try {
                            $currentCred.Drop()
                        } catch {
                            Stop-Function -Message "Error dropping credential $Name" -Target $name -Continue
                        }
                    } else {
                        Stop-Function -Message "Credential exists and Force was not specified" -Target $Name -Continue
                    }
                }


                if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating credential for database '$cred' on $instance")) {
                    try {
                        $credential = New-Object Microsoft.SqlServer.Management.Smo.Credential -ArgumentList $server, $Name
                        $credential.MappedClassType = $mappedClass
                        $credential.ProviderName = $ProviderName
                        $credential.Create($Identity, $SecurePassword)

                        Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                        Select-DefaultView -InputObject $credential -Property ComputerName, InstanceName, SqlInstance, Name, Identity, CreateDate, MappedClassType, ProviderName
                    } catch {
                        Stop-Function -Message "Failed to create credential in $cred on $instance" -Target $credential -InnerErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}