function Get-DbaCredential {
    <#
    .SYNOPSIS
        Retrieves SQL Server Credentials configured for external authentication and resource access.

    .DESCRIPTION
        Retrieves SQL Server Credentials that are stored securely on the server and used by SQL Server services to authenticate to external resources like file shares, web services, or other SQL Server instances. These credentials are essential for operations like backups to network locations, accessing external data sources, or running SQL Agent jobs that interact with external systems. The function returns detailed information about each credential including its name, associated identity, and provider configuration.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Filters results to only include SQL Server credentials with specific names. Accepts multiple credential names and supports wildcards.
        Use this when you need to check configuration for specific credentials like backup service accounts or external data source connections.
        Enclose names with spaces in quotes, such as "My Backup Credential".

    .PARAMETER ExcludeCredential
        Excludes SQL Server credentials with specified names from the results. Accepts multiple credential names to filter out.
        Useful when auditing all credentials except system or known service credentials that don't require review.

    .PARAMETER Identity
        Filters results to only include credentials that use specific Windows identities or SQL logins. Accepts multiple identity names.
        Use this to find all credentials associated with a particular service account or user across different credential objects.
        Enclose identities with spaces in quotes, such as "DOMAIN\Service Account".

    .PARAMETER ExcludeIdentity
        Excludes credentials that use specified Windows identities or SQL logins from the results. Accepts multiple identity names.
        Helpful when auditing credentials but excluding known system accounts or service identities from the output.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Security, Credential
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCredential

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Credential

        Returns one Credential object per credential found on the target SQL Server instance(s). This object represents SQL Server credentials stored in the database that are used for external resource access and authentication.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ID: Unique identifier for the credential within SQL Server
        - Name: The name of the SQL Server credential
        - Identity: The Windows identity, login, or external identity the credential uses (e.g., domain\account or Azure URI)
        - MappedClassType: The credential class type (None or CryptographicProvider for EKM)
        - ProviderName: The name of the cryptographic provider (if MappedClassType is CryptographicProvider)

        Additional properties available (from SMO Credential object):
        - CreateDate: DateTime when the credential was created
        - DateLastModified: DateTime when the credential was last modified
        - Parent: The Server object containing this credential
        - Properties: Collection of extended properties assigned to the credential
        - Urn: Uniform Resource Name identifier for the credential
        - State: The current state of the SMO object

        All properties from the base SMO Credential object are accessible even though only default properties are displayed without using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaCredential -SqlInstance localhost

        Returns all SQL Credentials on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaCredential -SqlInstance localhost, sql2016 -Name 'PowerShell Proxy'

        Returns the SQL Credentials named 'PowerShell Proxy' for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaCredential -SqlInstance localhost, sql2016 -Identity ad\powershell

        Returns the SQL Credentials for the account 'ad\powershell' on the local and sql2016 SQL Server instances

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Name')]
        [string[]]$Credential,
        [Alias('ExcludeName')]
        [string[]]$ExcludeCredential,
        [Alias('CredentialIdentity')]
        [string[]]$Identity,
        [Alias('ExcludeCredentialIdentity')]
        [string[]]$ExcludeIdentity,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $creds = $server.Credentials

            if ($Credential) {
                $creds = $creds | Where-Object { $Credential -contains $_.Name }
            }

            if ($ExcludeCredential) {
                $creds = $creds | Where-Object { $ExcludeCredential -notcontains $_.Name }
            }

            if ($Identity) {
                $creds = $creds | Where-Object { $Identity -contains $_.Identity }
            }

            if ($ExcludeIdentity) {
                $creds = $creds | Where-Object { $ExcludeIdentity -notcontains $_.Identity }
            }

            foreach ($currentcredential in $creds) {
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name ComputerName -value $currentcredential.Parent.ComputerName
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name InstanceName -value $currentcredential.Parent.ServiceName
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name SqlInstance -value $currentcredential.Parent.DomainInstanceName

                Select-DefaultView -InputObject $currentcredential -Property ComputerName, InstanceName, SqlInstance, ID, Name, Identity, MappedClassType, ProviderName
            }
        }
    }
}