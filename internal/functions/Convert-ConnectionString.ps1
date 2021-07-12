function Convert-Connectionstring ($str) {
    $newstring = @()
    $array = $str.Split(";")
    foreach ($item in $array) {
        $key = $item -split "=" | Select-Object -First 1
        $value = $item -split "=" | Select-Object -Last 1
        if ($key -in "Data Source", "Integrated Security", "Application Name") {
            $newstring += $key + "=" + $value
        } else {
            $newstring += $key.Replace(" ", "") + "=" + $value
        }
    }
    $newstring -join ";"
}