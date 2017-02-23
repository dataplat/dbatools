function ConvertFrom-DbaGlenBerryDMVCliXml
{
<#
.SYNOPSIS 
ConvertFrom-DbaGlennBerryDMVCliXml can convert clixml output from Get-DbaGlennBerryDMV to csv or excel

.DESCRIPTION
The default output format of Get-DbaGlennBerryDMV is clixml. It can also output to csv and excel. 
However, csv output can generate a lot of files and excel output depends on the ImportExcel module by Doug Fike (https://github.com/dfinke/ImportExcel)
ConvertFrom-DbaGlennBerryDMVCliXml can be used to convert from the default export type to the other available export types.
	
.EXAMPLE   
ConvertFrom-DbaGlennBerryDMVCliXml -clixmlfile c:\users\myusername\documents\myfilename.clixml -to excel -OutputLocation c:\users\myusername\documents\

Converts the specified clixml to possibly multiple excel sheets
If no OutputLocation is specified, the "My Documents" location will be used

.EXAMPLE   
ConvertFrom-DbaGlennBerryDMVCliXml -clixmlfile c:\users\myusername\documents\myfilename.clixml -to csv -OutputLocation c:\users\myusername\documents\

Converts the specified clixml to  multiple csv files
If no OutputLocation is specified, the "My Documents" location will be used

#>

Param(
    [parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_})]
    [System.IO.FileInfo]$clixmlfile,
    [ValidateSet(“excel”,”csv”)] 
    $to,
    [ValidateScript({Test-Path $_})]
    [System.IO.FileInfo]$OutputLocation = [Environment]::GetFolderPath("mydocuments"),
    [switch]$NoProgressBar
    )

    if ($to -eq "excel")
    {
        try
        {
            Import-Module ImportExcel -ErrorAction Stop
        }
        catch
        {
            Write-Output "Failed to load module, exporting to Excel feature is not available"
            Write-Output "Install the module from: https://github.com/dfinke/ImportExcel"
            Write-Output "Valid alternative conversion format is csv"
            break
        }
    }


    $sqlserver = $clixmlfile.BaseName.Split("_")[1]
    $clixml = Import-Clixml $clixmlfile
    $resultcounter = 0
    $resulttotal = $clixml.count

    Write-Output "Converting $($clixmlfile.fullname) into $to, destination: $outputlocation"

    foreach ($result in $clixml)
    {
        $resultcounter += 1
        if (!$NoProgressBar){Write-Progress -Id 0 -Activity "Exporting clixml resultsets to $to" -Status ("Result {0} of {1}" -f $resultcounter, $resulttotal) -CurrentOperation $result.Name -PercentComplete (($resultcounter / $resulttotal) * 100)}

        switch ($to)
        {
            "excel"
            {

                if ($result.dbSpecific)
                {
                    Write-Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3} ({4})"-f $to, $result.querynr, $result.Name, $sqlserver, $result.DatabaseName)
                    $result.result | Export-Excel -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$"))_$($result.DatabaseName).xlsx -WorkSheetname $($result.Name) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow   
                }
                else
                {
                    Write-Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3}"-f $to, $result.querynr, $result.Name, $sqlserver)
                    $result.result | Export-Excel -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$")).xlsx -WorkSheetname $($result.Name) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow   
                }

            }
            "csv"
            {
                if ($result.dbSpecific)
                {
                    Write-Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3} ({4})"-f $to, $result.querynr, $result.Name, $sqlserver, $result.DatabaseName)
                    $result | Export-Csv -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$"))_$($result.DatabaseName)_$($result.QueryNr)_$($result.Name.Replace(" ", "_")).csv -NoTypeInformation
                }
                else
                {
                    Write-Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3}"-f $to, $result.querynr, $result.Name, $sqlserver)
                    $result | Export-Csv -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$"))_$($result.QueryNr)_$($result.Name.Replace(" ", "_")).csv -NoTypeInformation
                }
            }
        } 
    }
}
