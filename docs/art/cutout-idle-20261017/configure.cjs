// Крепления подобраны по изометрическим частям; исходные пиксели не правятся.
const fs=require('node:fs'),path=require('node:path');
const a=72/(1268-695),b=72/(1232-641.5);
const layer=(id,crop,x,y,scale,amplitude_y=0,phase=0)=>({id,crop,position:[x,y],scale,amplitude_y,phase});
const rig={period_ms:3200,placement_note:'Approved 128x96 tile and Defender pose preserved. New figures face down-right in front three-quarter view. Trial 72px full-height envelope, body axis x=-2 and nearer boot lower edge y=17. Pose-specific fitting, not approved game anchors. Uniform scaling of each rigid part only.',variants:[
 {id:'a',title:'A · Бронзовый рыцарь',atlas:'atlas-a.png',layers:[
  layer('legs',[804,900,384,293],(279-455)*a-2,17-293*a,a),
  layer('torso',[162,695,531,480],(162-455)*a-2,-55,a,1),
  layer('head',[889,368,219,243],(361.925-455)*a-2,17-(1268-718.45)*a,.85*a,.6,.35)]},
 {id:'b',title:'B · Светлый минирыцарь',atlas:'atlas-b.png',layers:[
  layer('legs',[797,922,325,230],(217-370)*b-2,17-230*b,b),
  layer('torso',[141,830,499,301],(141-370)*b-2,17-(1232-830)*b,b,1),
  layer('head',[805,316,311,345],(210-370)*b-2,-55,.90*b,.65,.35)]}
]};
fs.writeFileSync(path.join(__dirname,'rig.json'),JSON.stringify(rig,null,2)+'\n');
