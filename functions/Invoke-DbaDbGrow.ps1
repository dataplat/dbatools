function Invoke-DbaDbGrow {
    <#
    .SYNOPSIS
        Grows all files in a database. Useful to proactively grow database files off-hours.
    
    .DESCRIPTION
        Grows all files in a database by set size, percentage or simply according to the file configuration.

        For the reasons why you should be doing it see
        https://www.sqlskills.com/blogs/paul/importance-of-data-file-size-management/
    
    .PARAMETER DatabaseFileSpace
        A list of files as produced by Get-DbaDatabaseFreeSpace which are to be grown

    .PARAMETER SqlInstance
        The SQL Server that you're connecting to.

    .PARAMETER SqlCredential
        SqlCredential object used to connect to the SQL Server as a different user.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - by default this list is empty

    .PARAMETER AllUserDatabases
        Run command against all user databases only. 

    .PARAMETER FileType
        Specifies the files types that will be grown

            All
                All Data and Log files are grown
            Data
                Just the Data files are grown
            Log
                Just the Log files are grown

    .PARAMETER When 
        Specifies then condition that needs to be met for the file to grow. By default it is set to 10% which means 
        when there is exactly or less free space in the file than 10% of the growth increment then the file will grow. 
        Always the grwoth setting is used to calculate whether the condition is met and the -By parameter is ignored in that regard.
        It can be set to an absolute value like 128MB and then the file will grow if the free space is at or below 128MB. 
        
        "Always" can be passed as value to ensure each file is grown regardless of conditions. Useful when piping files into the function.

    .PARAMETER By 
        Specifies by how much the file should grow. Valid values include 5%, 128MB. By default the By value is not set and the file
        growth configuration will be used to determin by how much it should grow. If no unit is specified bytes are assumed. 

        "Default" can be specified to explicitly use database file configuration.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Grow database file" on target "[pubs] on [SQL2016\VNEXT]".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Grow, Database
        Author: Michał Poręba

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbGrow

    .EXAMPLE
        Invoke-DbaDbGrow -SqlInstance sql2017 -Database 

    .EXAMPLE 
        Get-DbaDatabaseSpace -SqlInstance SQL2017 | Where { $_.FreeSpaceMB -lt 10 } | Invoke-DbaDbGrow

#>
}