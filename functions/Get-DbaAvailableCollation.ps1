function Get-DbaAvailableCollation {
    <#
    .SYNOPSIS
        Function to get available collations for a given SQL Server

    .DESCRIPTION
        The Get-DbaAvailableCollation function returns the list of collations available on each SQL Server.
        Only the connect permission is required to get this information.

    .PARAMETER SqlInstance
        TThe target SQL Server instance or instances. Only connect permission is required.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Collation, Configuration
        Author: Bryan Hamby (@galador)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAvailableCollation

    .EXAMPLE
        PS C:\> Get-DbaAvailableCollation -SqlInstance sql2016

        Gets all the collations from server sql2016 using NT authentication

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        #Functions to get/cache the code page and language description.
        #It runs about 9x faster caching these (2 vs 18 seconds) in my test,
        #since there are so many duplicates

        #No longer supported by Windows, but still shows up in SQL Server
        #http://www.databaseteam.org/1-ms-sql-server/982faddda7a789a1.htm
        $locales = @{66577 = "Japanese_Unicode" }
        $codePages = @{ }

        function Get-LocaleDescription ($LocaleId) {
            if ($locales.ContainsKey($LocaleId)) {
                $localeName = $locales.Get_Item($LocaleId)
            } else {
                try {
                    $localeName = (Get-Language $LocaleId).DisplayName
                } catch {
                    $localeName = $null
                }
                $locales.Set_Item($LocaleId, $localeName)
            }
            return $localeName
        }

        function Get-CodePageDescription ($codePageId) {
            if ($codePages.ContainsKey($codePageId)) {
                $codePageName = $codePages.Get_Item($codePageId)
            } else {
                try {
                    $codePageName = (Get-CodePage $codePageId).EncodingName
                } catch {
                    $codePageName = $null
                }
                $codePages.Set_Item($codePageId, $codePageName)
            }
            return $codePageName
        }
    }

    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $availableCollations = $server.EnumCollations()
            foreach ($collation in $availableCollations) {
                Add-Member -Force -InputObject $collation -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $collation -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $collation -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $collation -MemberType NoteProperty -Name CodePageName -Value (Get-CodePageDescription $collation.CodePage)
                Add-Member -Force -InputObject $collation -MemberType NoteProperty -Name LocaleName -Value (Get-LocaleDescription $collation.LocaleID)
            }

            Select-DefaultView -InputObject $availableCollations -Property ComputerName, InstanceName, SqlInstance, Name, CodePage, CodePageName, LocaleID, LocaleName, Description
        }
    }
}