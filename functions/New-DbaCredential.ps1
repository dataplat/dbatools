function New-DbaCredential {
    <#
.SYNOPSIS
Creates a new SQL Server credential

.DESCRIPTION
Creates a new credential

.PARAMETER SqlInstance
The target SQL Server(s)

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Name
The Credential name

.PARAMETER Identity
The Credential Identity

.PARAMETER Password
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
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.EXAMPLE
New-DbaCredential -SqlInstance Server1

You will be prompted to securely enter your password, then a credential will be created in the master database on server1 if it does not exist.

.EXAMPLE
New-DbaCredential -SqlInstance Server1 -Database db1 -Confirm:$false

Suppresses all prompts to install but prompts to securely enter your password and creates a credential in the 'db1' database

.EXAMPLE
New-DbaCredential -SqlInstance Server1 -Name AzureBackupBlobStore -Identity '<Azure Storage Account Name>' -Password (ConvertTo-SecureString '<Azure Storage Account Access Key>' -AsPlainText -Force)

Create credential on SQL Server 2012 CU2, SQL Server 2014 for use with BACKUP TO URL.
CredentialIdentity needs to be supplied with the Azure Storage Account Name.
Password needs to be one of the Access Keys for the account.

.EXAMPLE
New-DbaCredential -SqlInstance Server1 -Name 'https://<Azure Storage Account Name>.blob.core.windows.net/<Blob Store Container Name>' -Identity 'SHARED ACCESS SIGNATURE' -Password (ConvertTo-SecureString '<Shared Access Token>' -AsPlainText -Force)

Create Credential on SQL Server 2016 or higher for use with BACKUP TO URL.
Name has to be the full URL for the blob store container that will be the backup target.
Password needs to be passed the Shared Access Token (SAS Key).

#>
    [CmdletBinding(SupportsShouldProcess = $true)] #, ConfirmImpact = "High"
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Name = $Identity,
        [parameter(Mandatory)]
        [Alias("CredentialIdentity")]
        [string[]]$Identity,
        [Security.SecureString]$Password,
        [ValidateSet('CryptographicProvider', 'None')]
        [string]$MappedClassType = "None",
        [string]$ProviderName,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        $mappedclass = switch ($MappedClassType) {
            "CryptographicProvider" { 1 }
            "None" { 0 }
        }
    }

    process {
        if (!$Password) {
            Read-Host -AsSecureString -Prompt "Enter the credential password"
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($cred in $Identity) {
                $currentcred = $server.Credentials[$name]

                if ($currentcred) {
                    if ($force) {
                        Write-Message -Level Verbose -Message "Dropping credential $name"
                        $currentcred.Drop()
                    }
                    else {
                        Stop-Function -Message "Credential exists and Force was not specified" -Target $name -Continue
                    }
                }


                if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating credential for database '$cred' on $instance")) {
                    try {
                        $credential = New-Object Microsoft.SqlServer.Management.Smo.Credential -ArgumentList $server, $name
                        $credential.MappedClassType = $mappedclass
                        $credential.ProviderName = $ProviderName
                        $credential.Create($Identity, $Password)

                        Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name ComputerName -value $server.NetName
                        Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                        Select-DefaultView -InputObject $credential -Property ComputerName, InstanceName, SqlInstance, Name, Identity, CreateDate, MappedClassType, ProviderName
                    }
                    catch {
                        Stop-Function -Message "Failed to create credential in $cred on $instance. Exception: $($_.Exception.InnerException)" -Target $credential -InnerErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}
