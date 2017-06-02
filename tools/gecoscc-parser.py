#!/usr/bin/env python

from ConfigParser import ConfigParser
import re
import sys

# sys.argv[1] = configuration file
# sys.argv[2] = template file
# sys.argv[3] = substitution file
# sys.argv[4] = final file

conf_file = sys.argv[1] 
tmpl_file = sys.argv[2]
subs_file = sys.argv[3]
temp_file = sys.argv[4]

def readIniFile (ini_file):
    result = ConfigParser(defaults=None,
                         dict_type=dict,
                         allow_no_value=True
                         )
    result.read(ini_file)
    return result

def getValue (ini_file, section, option):
    value = ini_file.get(section, option, raw=True)
    if re.search(r'^\s', value):
        value = value.replace('\n','\n    ')
    return value

# read the substitution file
subst_f   = open(subs_file,'r')
subs_data = subst_f.read()
subst_f.close()

# first pass - config file
conf_data = readIniFile(conf_file)

for curr_section in conf_data.sections():
    extra_opts = ''

    for curr_option in conf_data.options(curr_section):
        if curr_option in subs_data:
            curr_value = getValue(conf_data, curr_section, curr_option)
            subs_data = subs_data.replace('${'+curr_section+'-'+curr_option+"}", curr_value)
        else:
            curr_value = getValue(conf_data, curr_section, curr_option)
            extra_opts += ('%s = %s\n' % (curr_option, curr_value))

    if extra_opts:
        subs_data = subs_data.replace('${'+curr_section+'-extras}', extra_opts)
    else:
        subs_data = subs_data.replace('${'+curr_section+'-extras}', '')

# second pass - template file
tmpl_data = readIniFile(tmpl_file)

for curr_section in tmpl_data.sections():
    for curr_option in tmpl_data.options(curr_section):
        if not conf_data.has_option(curr_section,curr_option):
            curr_value = getValue(tmpl_data, curr_section, curr_option)
            subs_data = subs_data.replace('${'+curr_section+'-'+curr_option+"}", curr_value)

# printing results
output_f  = open(temp_file,'w')
output_f.write(subs_data)
output_f.close()

