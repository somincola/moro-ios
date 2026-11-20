#include <metal_stdlib>
using namespace metal;

using Image = texture2d<float, access::sample>;
constexpr sampler inkSampler(coord::normalized, address::clamp_to_edge, filter::linear);
constant float tau = 6.28318530718;

float2 rotatePoint(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(c*p.x-s*p.y, s*p.x+c*p.y);
}

float luma(float3 rgb) { return dot(rgb,float3(.2126,.7152,.0722)); }

float2 coverUV(float2 uv, float destinationAspect, float imageAspect) {
    return (uv-.5)*float2(min(1.,destinationAspect/imageAspect),min(1.,imageAspect/destinationAspect))+.5;
}

float grain(float2 p) {
    float3 h=fract(float3(p.xyx)*float3(.1031,.1030,.0973));
    h+=dot(h,h.yzx+33.33);
    return fract((h.x+h.y)*h.z)-.5;
}

float3 headerFilm(float2 uv, float aspect, float phase, Image paper, Image ink) {
    float a=tau*phase;
    float breath=(1.-cos(a))*.5, lift=smoothstep(.08,.97,breath);
    float2 q=coverUV(uv,aspect,1914./822.);
    q=(q-.5)*(.927-.026*lift)+.5;
    float fold=smoothstep(-.25,.2,q.y-.29*q.x-.29);
    q+=float2(mix(.018,-.019,fold)*sin(a)+.006*cos(a+q.y*3.4),
              .012*cos(a+q.x*4.)+.011*sin(a+fold*2.2));
    float3 scene=paper.sample(inkSampler,q).rgb;
    float lightStripe=exp(-pow((q.x+.42*q.y-.31-.49*lift)/.235,2.));
    scene*=.972+.028*cos(a+2.9*q.x-1.4*q.y)+.050*lightStripe;
    scene+=float3(.010,.006,.002)*lightStripe*(1.-luma(scene));

    float2 p=(uv-.5)*float2(aspect,1.);
    p-=float2(.009*sin(a),.003+.006*cos(a));
    float2 bodyUV=rotatePoint(p,.017*sin(a+.22))/(.732+.018*lift)+.5;
    float2 hinge=float2(.675,.515);
    float2 earUV=rotatePoint(bodyUV-hinge,.024+.067*sin(a-.72))+hinge;
    earUV.x=hinge.x+(earUV.x-hinge.x)/(.952+.059*lift);
    earUV.y+=.005*cos(a-.4)-.003*lift;
    float2 key=normalize(float2(-.70+.35*lift,-.75));
    float2 cast=-key;
    float2 contact=cast*.009;
    float broad=ink.sample(inkSampler,bodyUV-cast*(.021+.008*lift)).b;
    float bodyShade=ink.sample(inkSampler,bodyUV-contact).r;
    float earShade=(ink.sample(inkSampler,earUV-cast*(.015+.020*lift)).g
                   +ink.sample(inkSampler,earUV-cast*(.021+.023*lift)).g)*.5;
    scene*=1.-.22*broad-.14*bodyShade-.20*earShade;
    float2 edge=cast*.0055;
    float3 darkEdge=float3(.64,.68,.75);
    scene=mix(scene,darkEdge,ink.sample(inkSampler,bodyUV-edge).r);
    scene=mix(scene,float3(.23,.32,.58),ink.sample(inkSampler,earUV-edge*1.6).g);

    float body=ink.sample(inkSampler,bodyUV).r;
    float ear=ink.sample(inkSampler,earUV).g;
    float rimBody=max(0.,body-ink.sample(inkSampler,bodyUV+key*.0022).r);
    float rimEar=max(0.,ear-ink.sample(inkSampler,earUV+key*.0035).g);
    float glaze=exp(-pow((bodyUV.x+.47*bodyUV.y-.49-.43*lift)/.21,2.));
    float warm=clamp(.46+(.55-bodyUV.y)*.67+.20*glaze+.060*lightStripe,0.,1.);
    float fiber=(paper.sample(inkSampler,float2(.09,.07)+(bodyUV-.5)*.105).g-.74)*.033;
    fiber+=grain(floor(bodyUV*1500.))*.007;
    float3 bodyColor=mix(float3(.869,.897,.926),float3(1.,.995,.979),warm)+fiber+.060*rimBody;
    float3 earColor=mix(float3(.315,.455,.829),float3(.61,.72,.988),.43+.30*lift+.16*(.55-earUV.y));
    scene=mix(scene,bodyColor,body);
    return mix(scene,earColor+fiber+.085*rimEar,ear);
}

kernel void exposeFrame(device uchar4 *out [[buffer(0)]],constant uint2 &size [[buffer(1)]],
                        constant float &phase [[buffer(2)]],
                        Image paper [[texture(0)]],Image ink [[texture(1)]],
                        uint2 pos [[thread_position_in_grid]]) {
    if(any(pos>=size)) return;
    float2 uv=(float2(pos)+.5)/float2(size);
    float aspect=float(size.x)/float(size.y);
    float3 rgb=headerFilm(uv,aspect,phase,paper,ink);
    out[pos.y*size.x+pos.x]=uchar4(uchar3(saturate(rgb)*255.+.5),uchar(255));
}
