get-wmiobject -class Lenovo_BiosSetting -namespace root\wmi | Select currentsetting | where currentsetting -ne "" | sort currentsetting
