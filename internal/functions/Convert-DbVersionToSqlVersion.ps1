function Convert-DbVersionToSqlVersion {
    <#
.SYNOPSIS
Internal function that makes db versions human readable

.DESCRIPTION
Internal function that makes db versions human readable

.PARAMETER dbversion
Analysis Server

.EXAMPLE
Convert-DbVersionToSqlVersion -dbversion 856

Returns "SQL Server vNext CTP1"

    #>
    param (
        [string]$dbversion
    )

    $dbversion = switch ($dbversion) {
        869 { "SQL Server 2017" }
        856 { "SQL Server vNext CTP1" }
        852 { "SQL Server 2016" }
        829 { "SQL Server 2016 Prerelease" }
        782 { "SQL Server 2014" }
        706 { "SQL Server 2012" }
        684 { "SQL Server 2012 CTP1" }
        661 { "SQL Server 2008 R2" }
        660 { "SQL Server 2008 R2" }
        655 { "SQL Server 2008 SP2+" }
        612 { "SQL Server 2005" }
        611 { "SQL Server 2005" }
        539 { "SQL Server 2000" }
        515 { "SQL Server 7.0" }
        408 { "SQL Server 6.5" }
        default { $dbversion }
    }

    return $dbversion
}