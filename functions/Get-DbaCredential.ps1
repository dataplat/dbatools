#ValidationTags#Messaging,FlowControl,CodeStyle#
function Get-DbaCredential {
    <#
        .SYNOPSIS
            Gets SQL Credential information for each instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaCredential command gets SQL Credential information for each instance(s) of SQL Server.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            SqlCredential object to connect as. If not specified, current Windows login will be used.

        .PARAMETER CredentialIdentity
            Auto-populated list of Credentials from Source. If no Credential is specified, all Credentials will be migrated.
            Note: if spaces exist in the credential name, you will have to type "" or '' around it. I couldn't figure out a way around this.

        .PARAMETER ExcludeCredentialIdentity
            Auto-populated list of Credentials from Source to be excluded from the migration

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Credential
            Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaCredential

        .EXAMPLE
            Get-DbaCredential -SqlInstance localhost

            Returns all SQL Credentials on the local default SQL Server instance

        .EXAMPLE
            Get-DbaCredential -SqlInstance localhost, sql2016

            Returns all SQL Credentials for the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$CredentialIdentity,
        [object[]]$ExcludeCredentialIdentity,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $credential = $server.Credentials

            if ($CredentialIdentity) {
                $credential = $credential | Where-Object $CredentialIdentity -Contains Name
            }

            if ($ExcludeCredentialIdentity) {
                $credential = $credential | Where-Object $CredentialIdentity -NotContains Name
            }

            foreach ($currentcredential in $credential) {
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name ComputerName -value $currentcredential.Parent.NetName
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name InstanceName -value $currentcredential.Parent.ServiceName
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name SqlInstance -value $currentcredential.Parent.DomainInstanceName

                Select-DefaultView -InputObject $currentcredential -Property ComputerName, InstanceName, SqlInstance, ID, Name, Identity, MappedClassType, ProviderName
            }
        }
    }
}