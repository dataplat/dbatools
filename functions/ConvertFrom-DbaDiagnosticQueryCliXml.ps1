function ConvertFrom-DbaDiagnosticQueryCliXml
{
<#
.SYNOPSIS 
ConvertFrom-DbaDiagnosticQueryCliXml can convert clixml output from Invoke-DbaDiagnosticQuery to CSV or Excel

.DESCRIPTION
The default output format of Invoke-DbaDiagnosticQuery is clixml. It can also output to CSV and Excel. 
However, CSV output can generate a lot of files and Excel output depends on the ImportExcel module by Doug Fike (https://github.com/dfinke/ImportExcel)
ConvertFrom-DbaDiagnosticQueryCliXml can be used to convert from the default export type to the other available export types.
	
.EXAMPLE  
ConvertFrom-DbaDiagnosticQueryCliXml -CliXmlFile c:\users\myusername\documents\myfilename.clixml -To Excel -OutputLocation c:\users\myusername\documents\

Converts the specified clixml to possibly multiple Excel sheets
If no OutputLocation is specified, the "My Documents" location will be used

.EXAMPLE  
ConvertFrom-DbaDiagnosticQueryCliXml -CliXmlFile c:\users\myusername\documents\myfilename.clixml -To Csv -OutputLocation c:\users\myusername\documents\

Converts the specified clixml to multiple CSV files
If no OutputLocation is specified, the "My Documents" location will be used

#>

Param(
  [parameter(Mandatory = $true)]
  [ValidateScript({Test-Path $_})]
  [System.IO.FileInfo]$CliXmlFile,
  [ValidateSet("Excel","Csv")]$To,
  [ValidateScript({Test-Path $_})]
  [System.IO.FileInfo]$OutputLocation = [Environment]::GetFolderPath("mydocuments"),
  [switch]$NoProgressBar,
  [switch]$Silent

  if ($to -eq "Excel")
  {
    try
    {
      Import-Module ImportExcel -ErrorAction Stop
    }
    catch
    {
      Write-Message -Level Output -Message "Failed to load module, exporting to Excel feature is not available"
      Write-Message -Level Output -Message "Install the module from: https://github.com/dfinke/ImportExcel"
      Write-Message -Level Output -Message "Valid alternative conversion format is csv"
      break
    }
  }


  $sqlserver = $clixmlfile.BaseName.Split("_")[1]
  $clixml = Import-Clixml $clixmlfile
  $resultcounter = 0
  $resulttotal = $clixml.count

  Write-Message -Level Output -Message "Converting $($clixmlfile.fullname) into $to, destination: $outputlocation"

  foreach ($result in $clixml)
  {
    $resultcounter += 1
    if (!$NoProgressBar){Write-Progress -Id 0 -Activity "Exporting clixml resultsets to $to" -Status ("Result {0} of {1}" -f $resultcounter, $resulttotal) -CurrentOperation $result.Name -PercentComplete (($resultcounter / $resulttotal) * 100)}

    switch ($to)
    {
      "Excel"
      {

        if ($result.dbSpecific)
        {
          Write-Message -Level Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3} ({4})"-f $to, $result.querynr, $result.Name, $sqlserver, $result.DatabaseName)
          $result.result | Export-Excel -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$"))_$($result.DatabaseName).xlsx -WorkSheetname $($result.Name) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow  
        }
        else
        {
          Write-Message -Level Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3}"-f $to, $result.querynr, $result.Name, $sqlserver)
          $result.result | Export-Excel -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$")).xlsx -WorkSheetname $($result.Name) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow  
        }

      }
      "csv"
      {
        if ($result.dbSpecific)
        {
          Write-Message -Level Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3} ({4})"-f $to, $result.querynr, $result.Name, $sqlserver, $result.DatabaseName)
          $result | Export-Csv -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$"))_$($result.DatabaseName)_$($result.QueryNr)_$($result.Name.Replace(" ", "_")).csv -NoTypeInformation
        }
        else
        {
          Write-Message -Level Verbose -Message ("Exporting clixml to {0}: {1:00} - {2} for Instance {3}"-f $to, $result.querynr, $result.Name, $sqlserver)
          $result | Export-Csv -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$"))_$($result.QueryNr)_$($result.Name.Replace(" ", "_")).csv -NoTypeInformation
        }
      }
    } 
  }
}
