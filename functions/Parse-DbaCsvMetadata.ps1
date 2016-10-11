function Get-UserPrompt {
    param (
        [string]$msg = "Would you like to continue?"
    ) 
    $choice = ""
    while ($choice -notmatch "[y|n]"){
        $choice = Read-Host "$msg (Y/N)"
        }
    
    if ($choice -eq "N"){
        Write-Warning "Good choice you made."
        exit
    }
    else 
    {
        Write-Warning "Continuing... Waaaaaa (╯°□°）╯︵ ┻━┻)"
    } 
}
  

function Parse-DbaCsvMetaData {
    <#

    .SYNOPSIS 

    Simple template



    .DESCRIPTION

    By default, all SQL Agent categories for Jobs, Operators and Alerts are copied.  



    .PARAMETER Csv

    CSV file to be processed. (Single, multiple file, if left blank dialog prompts for selection)



    .PARAMETER HeadersInRow

    The rownumber where the header is located. (0 means no header)



    .PARAMETER SpeedTest

    If set, it will read the entire file and outputs read / time statistics.


    .NOTES 

    Original Author: You (@YourTwitter, Yourblog.net)



    dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

    Copyright (C) 2016 Chrissy LeMaire



    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.



    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.



    You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.



    .LINK

    https://dbatools.io/Parse-DbaCSVMetadata



    .EXAMPLE

    Verb-DbaNoun -SqlServer sqlserver2014a

    Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 



    .EXAMPLE   

    Parse-DbaCsvMetaData

    Does this, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.



    .EXAMPLE   

    Parse-DbaCsvMetaData -csv C:\mycsvfile.csv -HeadersInRow 6 - Delimiter "`t"

    Opens mycsvfile.csv which has headers in the 6th row and tab delimited.

	

    .EXAMPLE   

    Parse-DbaCsvMetaData -Speedtest -Verbose | % { ("FileName: {0}{1}HasFieldsEnclosedInQuotes: {2}" -f $_.FileName , [System.Environment]::NewLine ,  $_.HasFieldsEnclosedInQuotes) , @( $_.Properties ) } | Format-Table -Property *

    Test mode, including speed test and verbose output (Select a Csv file on your system, won't bite I promise...) 

    #>
    [CmdletBinding()]
    param (
     $csv,
     [ValidateRange(0,100)] 
     $HeadersInRow = 1,
     [string]$Delimiter = ",",
     [switch]$SpeedTest
    )

    BEGIN 
    {
        # Load the basics
	    [void][Reflection.Assembly]::LoadWithPartialName("System.Data")
	    [void][Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
        Write-Verbose "[stopwatch] start"

        if (!$csv)
        {
            Write-Verbose "[csv file] No input, opening FileDialog."
	    	$fd = New-Object System.Windows.Forms.OpenFileDialog
	    	$fd.InitialDirectory = [environment]::GetFolderPath("MyDocuments")
	    	$fd.Filter = "CSV Files (*.csv;*.tsv;*.txt)|*.csv;*.tsv;*.txt"
	    	$fd.Title = "Select one or more CSV files"
	    	$fd.MultiSelect = $true
	    	$null = $fd.showdialog()
	    	$csv = $fd.FileNames
	    }

        # Initialise an empty array to hold the list of resolved csv paths
        $resolvedcsv = @()

        foreach ($file in $csv) 
        {
            $FileName = [IO.Path]::GetFileNameWithoutExtension($file)
	    	if(Test-Path $file) 
            {
                $resolvedcsv += (Resolve-Path $file).Path 
                Write-Verbose "[$FileName] File exists."
            }
            else 
            {
                Write-Warning "[$FileName] File does not exist removing from queue."
            }
	    }
        
	    $csv = $resolvedcsv
        if($csv.Length -eq 0) {
            Write-Warning "[csv file] File queue empty. Exiting."
        }
    }    

    PROCESS {

        $sw = [Diagnostics.Stopwatch]::StartNew()

        # Initialise an empty array to hold the metadata for single / multiple files.
        $MetaDataCollection = @()

        foreach ($file in $csv)
        {
            
            $FileName = [IO.Path]::GetFileNameWithoutExtension($file)        
            $sr = New-Object System.IO.StreamReader($file)      
            
            if ($HeadersInRow -gt 0) 
            {
                [int32]$i = 0
                while ($i -lt $HeadersInRow) 
                {
                    $Headers = $sr.readline()
                    $i = $i + 1
                }
            }
            $SampleRow = $sr.readline()
            [int32]$linecounter = 1
            
            if($speedtest)
            {
                while($sr.readline())
                {
                    [int32]$linecounter = $linecounter + 1
                }

                $secs = $sw.elapsed.TotalSeconds
                # Done! Format output then display
                $totalrows = $linecounter++
                $rs = "{0:N0}" -f [int]($totalrows / $secs)
                $rm = "{0:N0}" -f [int]($totalrows / $secs * 60)
                $mill = "{0:N0}" -f $totalrows        
                Write-Verbose "[stopwatch] $mill rows read in $([math]::round($secs,2)) seconds ($rs rows/sec and $rm rows/min)"
            }
            $sr.Close()
            $sr.Dispose()

            # Thanks for this, Bibek Lekhak! http://stackoverflow.com/questions/2402797/regex-find-characters-between
            $pattern = """\s*([^""]*)\s*"""

            if ($Headers)
            {
                Write-Verbose "checking header"
                $HasFieldsEnclosedInQuotes = ($Headers -match $pattern)
                $sr = New-Object System.IO.StringReader($Headers)
                $HeaderRowParser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($sr)
                $HeaderRowParser.HasFieldsEnclosedInQuotes = $HasFieldsEnclosedInQuotes
                $HeaderRowParser.Delimiters = $delimiter
                $HeaderColumns = $HeaderRowParser.ReadFields()
                $HeaderColumnsCount = $HeaderColumns.Count            
                $HeaderRowParser.Close()
                $HeaderRowParser.Dispose()
                $sr.Close()
                $sr.Dispose()    
            }

            if ($SampleRow)
            {
                $HasFieldsEnclosedInQuotes = ($SampleRow -match $pattern)
                $sr = New-Object System.IO.StringReader($SampleRow)
                $SampleRowParser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($sr)
                $SampleRowParser.HasFieldsEnclosedInQuotes = $HasFieldsEnclosedInQuotes
                $SampleRowParser.Delimiters = $delimiter
                $RowColumns = $SampleRowParser.ReadFields()
                $RowColumnsCount = $RowColumns.Count            
                $SampleRowParser.Close()
                $SampleRowParser.Dispose()
                $sr.Close()
                $sr.Dispose()    
            }

            $results = @()

            if ($Headers)
            {
                if($HeaderColumnsCount -eq $RowColumnsCount)
                {
                    Write-Verbose ("[$FileName] Header and sample row column count matching H:{0} R:{1}" -f $HeaderColumnsCount , $RowColumnsCount)
                }
                elseif($HeaderColumnsCount -gt $RowColumnsCount)
                {
                    Write-Warning ("[$FileName] More header than row column. H:{0} R:{1}" -f $HeaderColumnsCount , $RowColumnsCount)
                    Write-Warning "[$FileName] Stripping out headers."
                    $HeaderColumns = $null
                    Get-UserPrompt
                }
                else
                {   
                    Write-Warning ("[$FileName] More header than row column. H:{0} R:{1} unable to match" -f $HeaderColumnsCount , $RowColumnsCount)
                    Write-Warning "[$FileName] Stripping out headers."
                    Get-UserPrompt
                    $HeaderColumns = $null                 
                }
            }
            else
            {
                Write-Verbose "[$FileName] No header specified, skipping header and sample row column comparison." 
            }
            
            $RowColumnsCount = $RowColumnsCount -1

            (0..$RowColumnsCount) | foreach `
            -Begin { Write-Verbose "[$FileName] Generating metadata (Header name, length, data type matrix)." }   `             `
            -Process ` {
                $HeaderNumber = "Column"+ ($_ + 1)
                try
                {
                    $HeaderName = $HeaderColumns[$_]
                }
                catch {}
                #  [char]      A Unicode 16-bit character
                #  [byte]      An 8-bit unsigned character
                #  [int]       32-bit signed integer
                #  [long]      64-bit signed integer
                #  [bool]      Boolean True/False value
                #  [decimal]   A 128-bit decimal value
                #  [single]    Single-precision 32-bit floating point number
                #  [double]    Double-precision 64-bit floating point number
                #  [DateTime]  Date and Time
                #  [string]    Fixed-length string of Unicode characters
                
                $hash = [pscustomobject]@{
                    NumberedHeader = $HeaderNumber    
                    NamedHeader = $HeaderName
                    SampleValue = $RowColumns[$_]
                    SampleLength = $RowColumns[$_].Length
                    char = ([char]::TryParse($RowColumns[$_], [ref]0))
                    byte = ([byte]::TryParse($RowColumns[$_], [ref]0))
                    int16 = ([int16]::TryParse($RowColumns[$_], [ref]0))
                    int32 = ([int32]::TryParse($RowColumns[$_], [ref]0))
                    long = ([long]::TryParse($RowColumns[$_], [ref]0))
                    bool = ([bool]::TryParse($RowColumns[$_], [ref]0))
                    decimal = ([decimal]::TryParse($RowColumns[$_], [ref]0))
                    single = ([single]::TryParse($RowColumns[$_], [ref]0))
                    double = ([double]::TryParse($RowColumns[$_], [ref]0))
                    DateTime = ([DateTime]::TryParse($RowColumns[$_], [ref]0))
                    string = $true
                }
                $results += $hash
            } `
            -end { Write-Verbose "[csv file] Combining metadata." }
            $hash = [pscustomobject]@{    
                FileName = $FileName
                HasFieldsEnclosedInQuotes = $HasFieldsEnclosedInQuotes
                Properties = $results
            }
            $MetaDataCollection += $hash
        }
        
        if($MetaDataCollection.Count -gt 1) 
        {
            
            Write-Verbose "[csv file] Comparing the column length of the csv files."
            for ($i = 0; $i -lt $MetaDataCollection.Count -1; $i++) 
            {
                $current = $MetaDataCollection[$i]
                $next = $MetaDataCollection[$i+1]

                $msg = ("[csv file] Match {0} [{1}], {2} [{3}]" -f $current.FileName, $current.Properties.length, $next.FileName , $next.Properties.length)
                if ($current.Properties.length -eq $next.Properties.length) 
                {
                    Write-Verbose $msg
                }
                else 
                {
                    Write-Warning $msg.Replace("Match","Difference between")
                    Get-UserPrompt
                }
            }
        }
        $sw.Stop()
        Write-Verbose ("[stopwatch] All process complete. Elapsed: {0}" -f $sw.Elapsed)
        
    }

    END 
    {
        if ($abort)
        {
            Write-Verbose "[csv file] No CSV file selected, aborted."
            return
        }
        return $MetaDataCollection
    }
}

# This is a test output
#$csvlist = get-content 'C:\Users\freee\Documents\csvlist.txt'
#Parse-DbaCsvMetaData -Verbose  | % { ("FileName: {0}{1}HasFieldsEnclosedInQuotes: {2}" -f $_.FileName , [System.Environment]::NewLine ,  $_.HasFieldsEnclosedInQuotes) , @( $_.Properties ) } | Format-Table -Property *
