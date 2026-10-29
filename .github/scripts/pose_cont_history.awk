# Draw two FSC-versus-time panels from escaped, numeric TSV produced by Bash/jq.
BEGIN {FS="\t"; arms[1]="default";arms[2]="yes";arms[3]="only";
    colors[1]="#2563eb";colors[2]="#d97706";colors[3]="#15803d";
    dash[1]="none";dash[2]="6 3";dash[3]="2 3"}
{n++;number[n]=$1;attempt[n]=$2;created[n]=$3;url[n]=$5;stamp[n]=$6;
 for(i=1;i<=6;i++)value[n,i]=$(6+i)}
END {
 print "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 820 330\" role=\"img\" aria-labelledby=\"fsc-trend-title fsc-trend-desc\" style=\"display:block;width:100%;max-width:820px;height:auto;background:white\">"
 print "<title id=\"fsc-trend-title\">FSC resolution over time</title>"
 print "<desc id=\"fsc-trend-desc\">FSC 0.5 and 0.143 resolution in Å; lower is better. Missing values interrupt lines. Each point links to its Actions run.</desc>"
 print "<g font-family=\"sans-serif\" font-size=\"11\" fill=\"#374151\"><text x=\"12\" y=\"18\" font-size=\"14\">FSC resolution over time — lower is better</text>"
 for(a=1;a<=3;a++){
   x=460+110*(a-1)
   printf "<line x1=\"%d\" y1=\"14\" x2=\"%d\" y2=\"14\" stroke=\"%s\" stroke-width=\"2\" stroke-dasharray=\"%s\"/><text x=\"%d\" y=\"18\">%s</text>\n",x,x+22,colors[a],dash[a],x+28,arms[a]
 }
 for(panel=0;panel<2;panel++){
   left=62+410*panel;top=60;width=325;height=205;criterion=panel==0?"0.5":"0.143"
   printf "<text x=\"%d\" y=\"44\" font-size=\"13\">FSC=%s (Å)</text>\n",left,criterion
   found=0;low=0;high=0
   for(r=1;r<=n;r++)for(a=1;a<=3;a++){
     v=value[r,panel*3+a];if(v=="")continue
     if(!found || v+0<low)low=v+0;if(!found || v+0>high)high=v+0;found=1
   }
   if(!found){printf "<text x=\"%d\" y=\"160\">No FSC values available</text>\n",left+30;continue}
   padding=(high-low)*0.15;if(high*0.005>padding)padding=high*0.005;if(padding<0.01)padding=0.01
   low-=padding;if(low<0)low=0;high+=padding;span=stamp[n]-stamp[1]
   for(r=1;r<=n;r++)xs[r]=left+(span?width*(stamp[r]-stamp[1])/span:width/2)
   for(tick=0;tick<5;tick++){
     v=low+(high-low)*tick/4;y=top+height*(1-tick/4)
     printf "<line x1=\"%d\" y1=\"%.2f\" x2=\"%d\" y2=\"%.2f\" stroke=\"#e5e7eb\"/><text x=\"%d\" y=\"%.2f\" text-anchor=\"end\">%.3f</text>\n",left,y,left+width,y,left-8,y+4,v
   }
   printf "<path d=\"M %d %d V %d H %d\" fill=\"none\" stroke=\"#9ca3af\"/>\n",left,top,top+height,left+width
   for(tick=0;tick<(span?3:1);tick++){
     fraction=span?tick/2:0.5;x=left+width*fraction
     anchor=fraction==0?"start":fraction==1?"end":"middle"
     printf "<text x=\"%.2f\" y=\"285\" text-anchor=\"%s\" font-size=\"9\">%s</text>\n",x,anchor,strftime("%Y-%m-%d %H:%M",stamp[1]+span*fraction)
   }
   printf "<text x=\"%.2f\" y=\"315\" text-anchor=\"middle\">Run started (UTC)</text>\n",left+width/2
   for(a=1;a<=3;a++){
     previous=0
     for(r=1;r<=n;r++){
       v=value[r,panel*3+a];if(v==""){previous=0;continue}
       x=xs[r];y=top+height*(high-v)/(high-low)
       if(previous)printf "<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" stroke=\"%s\" stroke-width=\"2\" stroke-dasharray=\"%s\"/>\n",px,py,x,y,colors[a],dash[a]
       previous=1;px=x;py=y
       printf "<a href=\"%s\"><title>Run #%s, %s, %s: FSC=%s at %g Å</title>\n",url[r],number[r],arms[a],created[r],criterion,v
       if(a==1)printf "<circle cx=\"%.2f\" cy=\"%.2f\" r=\"6\"",x,y
       else if(a==2)printf "<rect x=\"%.2f\" y=\"%.2f\" width=\"8\" height=\"8\"",x-4,y-4
       else printf "<path d=\"M %.2f %.2f L %.2f %.2f L %.2f %.2f Z\"",x,y-3,x-3,y+3,x+3,y+3
       printf " fill=\"white\" stroke=\"%s\" stroke-width=\"1.5\"/></a>\n",colors[a]
     }
   }
 }
 print "</g></svg>"
}
