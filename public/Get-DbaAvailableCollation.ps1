function Get-DbaAvailableCollation {
    <#
    .SYNOPSIS
        Retrieves all available collations from SQL Server instances with detailed locale and code page information

    .DESCRIPTION
        Returns the complete list of collations supported by each SQL Server instance, along with their associated code page names, locale descriptions, and detailed properties.
        This information is essential when creating new databases, changing database collations, or planning migrations where collation compatibility matters.
        The function enhances the raw collation data with human-readable code page and locale descriptions to help DBAs make informed collation choices.
        Only connect permission is required to retrieve this information.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Only connect permission is required.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Collation

        Returns one collation object per collation supported by each SQL Server instance, enhanced with human-readable descriptions.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server service name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The collation name (e.g., SQL_Latin1_General_CP1_CI_AS)
        - CodePage: The numeric code page identifier (e.g., 1252 for Latin1)
        - CodePageName: Human-readable code page encoding name (e.g., iso-8859-1)
        - LocaleID: The numeric locale identifier (LCID) representing the language/culture
        - LocaleName: Human-readable locale/language name (e.g., English_United States, Japanese_Unicode)
        - Description: SQL Server collation description with sorting and case sensitivity information

        Additional properties available from SMO Collation object (use Select-Object * to access):
        - BinaryOrder: Boolean indicating if the collation uses binary sort order
        - BuiltInComparisonStyle: The comparison style constant used by SQL Server
        - IsCodePageCompatible: Boolean indicating code page compatibility
        - IsCaseSensitive: Boolean indicating if the collation is case-sensitive
        - IsAccentSensitive: Boolean indicating if the collation is accent-sensitive
        - IsKanaTypeSensitive: Boolean indicating if the collation distinguishes between Hiragana and Katakana
        - IsWidthSensitive: Boolean indicating if the collation distinguishes between full-width and half-width characters

        All properties from the base SMO Collation object are accessible even though only default properties are displayed without using Select-Object *.

    .NOTES
        Tags: Collation, Configuration, Management
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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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