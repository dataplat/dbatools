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
  

function Get-CSVMetaData 
{
    [CmdletBinding()]
    param (
     $csv,
     [ValidateRange(-1,1000)] 
     $HeadersInRow = 1,
     [string]$Delimiter = ",",
     [bool]$HasFieldsEnclosedInQuotes = $False,
     [switch]$DataTypes,
     [switch]$TableOutput,
     [switch]$Speedtest
    )

    # Load the basics
	[void][Reflection.Assembly]::LoadWithPartialName("System.Data")
	[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    Write-Verbose "[stopwatch] start"
    $sw = [Diagnostics.Stopwatch]::StartNew()

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
		if (!$csv) 
        { 
            Write-Warning "[csv file] No CSV file selected." 
        }
	}
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
    if ($TableOutput)
    {
        return $MetaDataCollection | % { ("FileName: {0}{1}HasFieldsEnclosedInQuotes: {2}" -f $_.FileName , [System.Environment]::NewLine ,  $_.HasFieldsEnclosedInQuotes) , @( $_.Properties ) } | Format-Table -Property *
    }
    $sw.Stop()
    Write-Verbose ("[stopwatch] All process complete. Elapsed: {0}" -f $sw.Elapsed)
    return $MetaDataCollection
}

$csv = 'C:\s3-downloads\Out-of-Stock\Complete_Demographic_Data.txt'

# This is a test output
#$csvlist = get-content "C:\Users\freee\Documents\csvlist.txt"
Get-CSVMetaData -HeadersInRow 1 -Delimiter "," -Speedtest -DataTypes -Verbose | % { ("FileName: {0}{1}HasFieldsEnclosedInQuotes: {2}" -f $_.FileName , [System.Environment]::NewLine ,  $_.HasFieldsEnclosedInQuotes) , @( $_.Properties ) } | Format-Table -Property *
#
#Measure-Command {Get-CSVMetaData -HeadersInRow 10 -HasFieldsEnclosedInQuotes $false -csv "C:\Users\freee\Documents\Fielding.csv" -Verbose}
#Measure-Command {Get-CSVMetaData -HeadersInRow 10 -HasFieldsEnclosedInQuotes $true -csv "C:\Users\freee\Documents\Fielding.csv" -Verbose}
#Measure-Command {Get-CSVMetaData -HeadersInRow 10 -HasFieldsEnclosedInQuotes $false -csv "C:\Users\freee\Documents\Sample - Superstore Sales (Excel).csv" -Verbose}
#Measure-Command {Get-CSVMetaData -HeadersInRow 10 -HasFieldsEnclosedInQuotes $true -csv "C:\Users\freee\Documents\Sample - Superstore Sales (Excel).csv" -Verbose}


#Sample - Superstore Sales (Excel).csv

#$form = New-Object System.Windows.Forms.Form
#$form.AutoSize =$true
#
#$list = New-Object System.collections.ArrayList
#$list.AddRange($results)
#
#$dataGridView = New-Object System.Windows.Forms.DataGridView -Property @{
#    Size=New-Object System.Drawing.Size(1050,400)
#    ColumnHeadersVisible = $true
#    DataSource = $list
#    AutoSizeColumnsMode = 'AllCells'
#    }
#
#
#
###$dataGridView.ColumnCount
###$dataGridView.RowCount
###$dataGridView.Rows[2].Cells[2].FormattedValue 
###
##
###= 'White' #.ToString()
##
##$cellstyle = New-Object System.Windows.Forms.DataGridViewBindingCompleteEventArgs
##$cellstyle.BackColor = 'Green'
##$cellstyle.ForeColor = 'Red'
##
##
##
##
##$i = 0
##$j = 0
##while ($i -lt 1) {
##        while ($j -lt 1) {
##        $dataGridView.Rows.Item(1).cells.Item(1).style = $cellstyle
##        $dataGridView.Show()
##        $cellstyle 
##        $j++
##        $j 
##    }
##    $i++
##    $i
##}
#
#$form.Controls.Add($dataGridView)
#$form.ShowDialog()



