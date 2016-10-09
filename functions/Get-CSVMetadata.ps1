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
     [switch]$noreturn
    )

    # Load the basics
	[void][Reflection.Assembly]::LoadWithPartialName("System.Data")
	[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

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
        
        $sr = New-Object System.IO.StreamReader(Get-Item $file)
        
        if ($HeadersInRow -gt 0) 
        {
            $i = 0
            while ($i -lt $HeadersInRow) 
            {
                $Headers = $sr.readline()
                $i++
            }
        }
        $SampleRow = $sr.readline()
        $sr.Close()
        $sr.Dispose()

        # Thanks for this, Chris! http://www.schiffhauer.com/c-split-csv-values-with-a-regular-expression/
        $pattern = "((?<=`")[^`"]*(?=`"($delimiter|$)+)|(?<=$delimiter|^)[^$delimiter`"]*(?=$delimiter|$))"
        
        if ($SampleRow -match $pattern -or $Headers -match $pattern) 
        {
            Write-Verbose "[$FileName] The CSV file appears quote identified."
            $HasFieldsEnclosedInQuotes = $true
        }


        if ($Headers)
        {
            $sr = New-Object System.IO.StringReader($Headers)
            $HeaderRowParser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($sr)
            $HeaderRowParser.HasFieldsEnclosedInQuotes = $HasFieldsEnclosedInQuotes
            $HeaderRowParser.Delimiters = $delimiter
            $HeaderColumns = $HeaderRowParser.ReadFields()
            $HeaderRowParser.Close()
            $HeaderRowParser.Dispose()
            $sr.Close()
            $sr.Dispose()    
        }

        if ($SampleRow)
        {
            $sr = New-Object System.IO.StringReader($SampleRow)
            $SampleRowParser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($sr)
            $SampleRowParser.HasFieldsEnclosedInQuotes = $HasFieldsEnclosedInQuotes
            $SampleRowParser.Delimiters = $delimiter
            $RowColumns = $SampleRowParser.ReadFields()
            $SampleRowParser.Close()
            $SampleRowParser.Dispose()
            $sr.Close()
            $sr.Dispose()    
        }

        $results = @()

        if ($Headers)
        {
            if($HeaderColumns.Length -eq $RowColumns.Length)
            {
                Write-Verbose ("[$FileName] Header and sample row column count matching H:{0} R:{1}" -f $HeaderColumns.Length , $RowColumns.Length)
            }
            elseif($HeaderColumns.Length -gt $RowColumns.Length)
            {
                Write-Warning ("[$FileName] More header than row column. H:{0} R:{1}" -f $HeaderColumns.Length , $RowColumns.Length)
                Write-Warning "[$FileName] Stripping out headers."
                $HeaderColumns = $null
                Get-UserPrompt
            }
            else
            {   
                Write-Warning ("[$FileName] More header than row column. H:{0} R:{1} unable to match" -f $HeaderColumns.Length , $RowColumns.Length)
                Write-Warning "[$FileName] Stripping out headers."
                Get-UserPrompt
                $HeaderColumns = $null                 
            }
        }
        else
        {
            Write-Verbose "[$FileName] No header specified, skipping header and sample row column comparison." 
        }
        
        Write-Verbose "[$FileName] Generating metadata (Header name, length, data type matrix)."
        
        foreach ($column in $RowColumns) 
        {
            try 
            {                
                $HeaderName = $HeaderColumns[$RowColumns.indexof($column)]
            } 
            catch 
            {
                $HeaderName = ("Column" + ($RowColumns.indexof($column) + 1))
            }

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
    
            $hash = New-Object System.Object    
            $hash | Add-Member -type NoteProperty -name HeaderName -value $HeaderName
            $hash | Add-Member -type NoteProperty -name SampleValue -value $Column
            $hash | Add-Member -type NoteProperty -name SampleLenght -value $Column.Length
            $hash | Add-Member -type NoteProperty -name [char] -value ([char]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [byte] -value ([byte]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [int16] -value ([int16]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [int32] -value ([int32]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [long] -value ([long]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [bool] -value ([bool]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [decimal] -value ([decimal]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [single] -value ([single]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [double] -value ([double]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [DateTime] -value ([DateTime]::TryParse($Column, [ref]0))
            $hash | Add-Member -type NoteProperty -name [string] -value $true

            $results += $hash
            $i = $i + 1
            #$results
        }
        
        $hash = New-Object System.Object    
        $hash | Add-Member -type NoteProperty -name FileName -value $FileName
        $hash | Add-Member -type NoteProperty -name HasFieldsEnclosedInQuotes -Value $HasFieldsEnclosedInQuotes
        $hash | Add-Member -type NoteProperty -name Properties -value $results
        $MetaDataCollection += $hash
    }
    
    if($MetaDataCollection.Count -gt 1) 
    {
        Write-Verbose "[csv file] All Metadata combined into an object."
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
    return $MetaDataCollection
}

# This is a test output
Get-CSVMetaData -HeadersInRow 1 | % { ("FileName: {0}{1}HasFieldsEnclosedInQuotes: {2}" -f $_.FileName , [System.Environment]::NewLine ,  $_.HasFieldsEnclosedInQuotes) , @( $_.Properties ) } | Format-Table -Property *


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



