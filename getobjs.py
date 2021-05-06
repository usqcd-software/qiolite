import sys, os, json

csrc = "lib"
if len(sys.argv) > 1:
    csrc = sys.argv[1]

with open(csrc+'/qioc.json') as f:
    js = json.load(f)
    objs = js["link"]
    print(objs)
    with open(csrc+'/make.objs',"w") as fo:
        fo.write("OBJS =")
        for o in objs:
            s = o.replace("@","")
            #print(s)
            if s != o:
                #print("not equal")
                os.rename(o.strip(".o"), s.strip(".o"))
                o = s
            b = os.path.basename(o)
            print(b)
            fo.write(" "+b)
        fo.write("\n")
        fo.close()
    f.close()
