# Prints the texts, content descriptions and clickable areas from a uiautomator dump (stdin).
import sys,re
x=sys.stdin.read()
g=lambda k,n:(re.search(k+r'="([^"]*)"',n) or [0,""])[1]
for m in re.finditer(r'<node [^>]*>',x):
  n=m.group(0); t=g(' text',n); d=g('content-desc',n); b=g('bounds',n); c='C' if 'clickable="true"' in n else ' '
  if t or d or c=='C': print(c,b,t,'|',d)
