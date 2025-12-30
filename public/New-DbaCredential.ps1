function New-DbaCredential {
    <#
    .SYNOPSIS
        Creates a SQL Server credential for authentication to external resources

    .DESCRIPTION
        Creates a SQL Server credential that stores authentication information for connecting to external resources like Azure storage accounts, network shares, or service accounts. Credentials are commonly used for backup to URL operations, SQL Agent job authentication, and accessing external data sources. The function supports various authentication methods including traditional username/password, Azure storage access keys, SAS tokens, and managed identities.

    .PARAMETER SqlInstance
        The target SQL Server(s)

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies the name for the SQL Server credential object. Defaults to the Identity value if not provided.
        Use a descriptive name that identifies the purpose, like 'AzureBackupStorage' or 'NetworkShareAccess'.

    .PARAMETER Identity
        Defines the authentication identity for the credential. Can be a Windows account, service account, Azure storage URI, or special values like 'SHARED ACCESS SIGNATURE' or 'Managed Identity'.
        For Azure backup scenarios, use the full blob container URI or SAS/Managed Identity authentication methods.

    .PARAMETER SecurePassword
        Provides the password or access key as a SecureString for credential authentication. Required for most authentication methods except Managed Identity.
        For Azure storage, this would be the access key or SAS token. Use Get-Credential or ConvertTo-SecureString to create the SecureString.

    .PARAMETER MappedClassType
        Specifies the credential mapping class type. Use 'CryptographicProvider' for credentials that will use cryptographic providers, or 'None' for standard credentials.
        Most common scenarios use 'None' (default). Only specify 'CryptographicProvider' when working with EKM or custom cryptographic providers.

    .PARAMETER ProviderName
        Specifies the name of the cryptographic provider when MappedClassType is 'CryptographicProvider'.
        Only required when using Extensible Key Management (EKM) scenarios with third-party cryptographic providers.

    .PARAMETER Force
        Drops and recreates the credential if it already exists on the target instance.
        Use this when you need to update an existing credential's identity or password, as SQL Server credentials cannot be modified once created.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Credential, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Credential

        Returns one Credential object for each credential successfully created on the target instance. The credential object contains both SMO-level properties and dbatools-specific NoteProperties for connection context.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the credential
        - Identity: The authentication identity for the credential (account name, URI, or special value)
        - CreateDate: DateTime when the credential was created on the instance
        - MappedClassType: The mapped class type - 0 for None (standard credentials), 1 for CryptographicProvider (EKM scenarios)
        - ProviderName: The name of the cryptographic provider (if MappedClassType is CryptographicProvider)

        Additional properties available from the SMO Credential object:
        - Owner: The owner/principal that owns the credential
        - ID: The unique identifier for the credential within the instance
        - DateLastModified: DateTime when the credential was last modified
        - Urn: The Uniform Resource Name for the credential object
        - State: The current state of the SMO object (Existing, Creating, Deleting, etc.)

        All properties from the base SMO Credential object are accessible even though only default properties are displayed without using Select-Object *.

    .LINK
        https://dbatools.io/New-DbaCredential

    .EXAMPLE
        PS C:\> New-DbaCredential -SqlInstance Server1 -Name MyCredential -Identity "ad\user" -SecurePassword (Get-Credential NoUsernameNeeded).Password

        It will create a credential named "MyCredential" that as "ad\user" as identity and a password on server1 if it does not exist.

    .EXAMPLE
        PS C:\> New-DbaCredential -SqlInstance Server1 -Identity "MyIdentity"

        It will create a credential with identity value "MyIdentity" and same name but without a password on server1 if it does not exist.

    .EXAMPLE
        PS C:\> $params = @{
        >>SqlInstance = "Server1"
        >>Name = "AzureBackupBlobStore"
        >>Identity = "https://<Azure Storage Account Name>.blob.core.windows.net/<Blob Container Name>"
        >>SecurePassword = (Get-Credential NoUsernameNeeded).Password # <Azure Storage Account Access Key>
        >>}
        PS C:\> New-DbaCredential @params

        Creates a credential, "AzureBackupBlobStore", on Server1 using the Access Keys for Backup To URL. Identity must be the full URI for the blob container that will be the backup target. The SecurePassword supplied is one of the two Access Keys for the Azure Storage Account.

    .EXAMPLE
        PS C:\> $sasParams = @{
        >>SqlInstance = "server1"
        >>Name = "https://<azure storage account name>.blob.core.windows.net/<blob container>"
        >>Identity = "SHARED ACCESS SIGNATURE"
        >>SecurePassword = (Get-Credential NoUsernameNeeded).Password # <Shared Access Token>
        >>}
        PS C:\> New-DbaCredential @sasParams

        Create a credential on Server1 using a SAS token for Backup To URL. The Name is the full URI for the blob container that will be the backup target.
        The SecurePassword will be the Shared Access Token (SAS), as a SecureString.

    .EXAMPLE
        PS C:\> $managedIdentityParams = @{
        >>SqlInstance = "server1"
        >>Name = "https://<azure storage account name>.blob.core.windows.net/<blob container>"
        >>Identity = "Managed Identity"
        >>}
        PS C:\> New-DbaCredential @managedIdentityParams

        Create a credential on Server1 using a Managed Identity for Backup To URL. The Name is the full URI for the blob container that will be the backup target.
        As no password is needed in this case, we just don't pass the -SecurePassword parameter.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Name = $Identity,
        [parameter(Mandatory)]
        [Alias("CredentialIdentity")]
        [string]$Identity,
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
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $currentCred = $server.Credentials[$Name]

            if ($currentCred) {
                if ($force) {
                    Write-Message -Level Verbose -Message "Dropping credential $Name"
                    try {
                        if ($Pscmdlet.ShouldProcess($SqlInstance, "Dropping credential '$Name' on $instance")) {
                            $currentCred.Drop()
                        }
                    } catch {
                        Stop-Function -Message "Error dropping credential $Name" -Target $name -Continue
                    }
                } else {
                    Stop-Function -Message "Credential exists and Force was not specified" -Target $Name -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating credential '$Name' on $instance")) {
                try {
                    $instancecredential = New-Object Microsoft.SqlServer.Management.Smo.Credential -ArgumentList $server, $Name
                    try {
                        $instancecredential.MappedClassType = $mappedClass
                    } catch {
                        Add-Member -Force -InputObject $instancecredential -MemberType NoteProperty -Name MappedClassType -Value $mappedClass
                    }
                    $instancecredential.ProviderName = $ProviderName
                    if ($SecurePassword) {
                        Write-Message -Level Verbose -Message "Creating credential with identity '$Identity' with password"
                        $instancecredential.Create($Identity, $SecurePassword)
                    } else {
                        Write-Message -Level Verbose -Message "Password was not provided, creating credential with identity '$Identity' without password"
                        $instancecredential.Create($Identity)
                    }

                    Add-Member -Force -InputObject $instancecredential -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $instancecredential -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $instancecredential -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                    Select-DefaultView -InputObject $instancecredential -Property ComputerName, InstanceName, SqlInstance, Name, Identity, CreateDate, MappedClassType, ProviderName
                } catch {
                    Stop-Function -Message "Failed to create credential in $cred on $instance" -Target $instancecredential -InnerErrorRecord $_ -Continue
                }
            }
        }
    }
}