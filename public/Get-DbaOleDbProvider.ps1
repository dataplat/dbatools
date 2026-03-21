function Get-DbaOleDbProvider {
    <#
    .SYNOPSIS
        Retrieves OLE DB provider configurations registered with SQL Server for linked servers and distributed queries

    .DESCRIPTION
        Returns the OLE DB providers that SQL Server knows about and can use for external data connections like linked servers, distributed queries, and OPENROWSET operations. This is essential for auditing your server's connectivity capabilities and troubleshooting linked server connection issues. The function shows provider details including security settings like AllowInProcess and DisallowAdHocAccess, which control how SQL Server can use each provider. Use this when setting up linked servers or diagnosing why certain external data sources aren't accessible.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Provider
        Filters results to specific OLE DB provider names. Accepts an array of provider names for targeting multiple providers.
        Use this when you need to check configuration for specific providers like SQLNCLI11 or MSDASQL instead of listing all available providers.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, OLEDB
        Author: Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaOleDbProvider

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.OleDbProviderSettings

        Returns one OleDbProviderSettings object per OLE DB provider configured on the SQL Server instance.

        Default display properties (via Select-DefaultView):
        - ComputerName: Computer name of the SQL Server instance
        - InstanceName: SQL Server instance name
        - SqlInstance: Full SQL Server instance name (computer\instance format)
        - Name: OLE DB provider name (e.g., SQLNCLI11, MSDASQL, SSISOLEDB)
        - Description: Human-readable description of the provider
        - AllowInProcess: Boolean indicating if the provider is allowed to run in-process with SQL Server
        - DisallowAdHocAccess: Boolean indicating if ad hoc access (OPENROWSET, OPENDATASOURCE) is disallowed
        - DynamicParameters: Boolean indicating if the provider supports dynamic parameters
        - IndexAsAccessPath: Boolean indicating if the provider supports indexes as access paths
        - LevelZeroOnly: Boolean indicating if only level zero (table-level) operations are allowed
        - NestedQueries: Boolean indicating if the provider supports nested queries
        - NonTransactedUpdates: Boolean indicating if the provider supports non-transacted updates

        Additional properties available (from SMO OleDbProviderSettings object):
        - Parent: Reference to the parent Server object
        - Urn: The Uniform Resource Name of the provider object
        - Properties: Collection of property objects
        - State: Current state of the SMO object (Existing, Creating, Deleting, etc.)
        - Uid: Unique identifier for the provider setting

        All properties from the base SMO OleDbProviderSettings object are accessible using Select-Object * even though only the default properties are displayed without it.

    .EXAMPLE
        PS C:\> Get-DbaOleDbProvider -SqlInstance SqlBox1\Instance2

        Returns a list of all OleDb providers on SqlBox1\Instance2

    .EXAMPLE
        PS C:\> Get-DbaOleDbProvider -SqlInstance SqlBox1\Instance2 -Provider SSISOLEDB

        Returns the SSISOLEDB provider on SqlBox1\Instance2
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Provider,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Getting startup procedures for $servername"

            $providers = $server.Settings.OleDbProviderSettings

            if ($Provider) {
                $providers = $providers | Where-Object Name -in $Provider
            }

            foreach ($oledbprovider in $providers) {
                Add-Member -Force -InputObject $oledbprovider -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $oledbprovider -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $oledbprovider -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                Select-DefaultView -InputObject $oledbprovider -Property 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Description', 'AllowInProcess', 'DisallowAdHocAccess', 'DynamicParameters', 'IndexAsAccessPath', 'LevelZeroOnly', 'NestedQueries', 'NonTransactedUpdates'
            }
        }
    }
}