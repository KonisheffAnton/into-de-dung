"""Read-only pixel registration of the supplied Paint mockup; saves measurements."""
from pathlib import Path
from PIL import Image
import numpy as np,json
p=Path(__file__).resolve().parent
ref=np.array(Image.open(p/'user-reference.png').convert('RGB'))
result={'reference_size':[ref.shape[1],ref.shape[0]],'scale_of_exports':4,'placements':{}}
for name in ['tile','warrior']:
 source=np.array(Image.open(p/f'paint-{name}.png').convert('RGBA'))
 h,w=source.shape[:2]
 # У большого image_gen-спрайта почти вся фигура alpha253, не255.
 # Paint показывает её на белом; учитываем это вместо опоры на редкие255px.
 alpha=source[:,:,3]/255.
 rendered=np.round(source[:,:,:3]*alpha[:,:,None]+255*(1-alpha[:,:,None])).astype(np.int16)
 yy,xx=np.where(source[:,:,3]>=240)
 rng=np.random.default_rng(20261009)
 chosen=rng.choice(len(xx),size=min(800,len(xx)),replace=False)
 dy,dx=np.mgrid[0:ref.shape[0]-h+1,0:ref.shape[1]-w+1]
 votes=np.zeros(dx.shape,dtype=np.int32)
 for i in chosen:
  x,y=xx[i],yy[i]
  votes+=(np.abs(ref[dy+y,dx+x].astype(np.int16)-rendered[y,x]).max(axis=-1)<=3)
 y,x=np.unravel_index(votes.argmax(),votes.shape)
 visible=source[:,:,3]>=240
 close=np.abs(ref[y:y+h,x:x+w].astype(np.int16)-rendered).max(axis=-1)<=3
 result['placements'][name]={'origin':[int(x),int(y)],'sample_matches':int(votes[y,x]),'sample_size':len(chosen),'matching_near_opaque_pixels':int((close&visible).sum()),'near_opaque_pixels':int(visible.sum()),'best_candidate_count':int((votes==votes[y,x]).sum())}
result['cropped_warrior_origin_relative_to_cropped_tile_at_1x']=[(result['placements']['warrior']['origin'][i]-result['placements']['tile']['origin'][i])/4 for i in [0,1]]
result['note']='RGB translation vote with alpha>=240 composited on white and max channel difference3. No resizing fit. Tile is occluded by warrior; rough-cut defects reduce matches. Visual reference is authoritative, measurements describe this static pose only.'
(p/'reference-measurements.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
