function Get-Language ($id) {
	switch ($id) {
		1033 { $alias = "English"; $name = "us_english" }
		1031 { $alias = "German"; $name = "Deutsch" }
		1036 { $alias = "French"; $name = "Français" }
		1041 { $alias = "Japanese"; $name = "日本語" }
		1030 { $alias = "Danish"; $name = "Dansk" }
		3082 { $alias = "Spanish"; $name = "Español" }
		1040 { $alias = "Italian"; $name = "Italiano" }
		1043 { $alias = "Dutch"; $name = "Nederlands" }
		2068 { $alias = "Norwegian"; $name = "Norsk" }
		2070 { $alias = "Portuguese"; $name = "Português" }
		1035 { $alias = "Finnish"; $name = "Suomi" }
		1053 { $alias = "Swedish"; $name = "Svenska" }
		1029 { $alias = "Czech"; $name = "čeština" }
		1038 { $alias = "Hungarian"; $name = "magyar" }
		1045 { $alias = "Polish"; $name = "polski" }
		1048 { $alias = "Romanian"; $name = "română" }
		1050 { $alias = "Croatian"; $name = "hrvatski" }
		1051 { $alias = "Slovak"; $name = "slovenčina" }
		1060 { $alias = "Slovenian"; $name = "slovenski" }
		1032 { $alias = "Greek"; $name = "ελληνικά" }
		1026 { $alias = "Bulgarian"; $name = "български" }
		1049 { $alias = "Russian"; $name = "русский" }
		1055 { $alias = "Turkish"; $name = "Türkçe" }
		2057 { $alias = "British English"; $name = "British" }
		1061 { $alias = "Estonian"; $name = "eesti" }
		1062 { $alias = "Latvian"; $name = "latviešu" }
		1063 { $alias = "Lithuanian"; $name = "lietuvių" }
		1046 { $alias = "Brazilian"; $name = "Português (Brasil)" }
		1028 { $alias = "Traditional Chinese"; $name = "繁體中文" }
		1042 { $alias = "Korean"; $name = "한국어" }
		2052 { $alias = "Simplified Chinese"; $name = "简体中文" }
		1025 { $alias = "Arabic"; $name = "Arabic" }
		1054 { $alias = "Thai"; $name = "ไทย" }
		1044 { $alias = "Bokmål"; $name = "norsk (bokmål)" }
		default { $alias = "English"; $name = "us_english" }
	}
	
	[pscustomobject]@{
		LanguageID    = $id
		Alias		  = $alias
		Name		  = $name
	}
}