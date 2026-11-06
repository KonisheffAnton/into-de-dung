(() => {
  'use strict';
  const specs = {
    fire24:{pending:true,frames:[],loop:false,autoplay:false},
    fire29:{pending:true,frames:[],loop:false,autoplay:false},
    trap01:{frames:[
      {src:'trap/closed.png',ms:600,label:'Шипы убраны'},
      {src:'trap/half.png',ms:450,label:'Шипы наполовину выдвинуты'},
      {src:'trap/extended.png',ms:null,label:'Шипы выдвинуты'}
    ],loop:false,autoplay:false},
    caltrops03:{frames:[
      {src:'caltrops/rest.png',ms:5000,label:'Покой'},
      {src:'caltrops/glint-low-peak.png',ms:150,label:'Нижний блик'},
      {src:'caltrops/glint-low-tail.png',ms:150,label:'Нижний блик затухает'},
      {src:'caltrops/rest.png',ms:5000,label:'Покой'},
      {src:'caltrops/glint-high-peak.png',ms:150,label:'Верхний блик'},
      {src:'caltrops/glint-high-hold.png',ms:150,label:'Верхний блик удерживается'},
      {src:'caltrops/rest.png',ms:5000,label:'Покой'}
    ],loop:true,autoplay:true}
  };
  class Clip {
    constructor(id,spec){
      this.card=document.getElementById(id);this.spec=spec;this.image=this.card.querySelector('.moving');
      this.status=this.card.querySelector('.status');this.playButton=this.card.querySelector('.play');
      this.restartButton=this.card.querySelector('.restart');this.glintsButton=this.card.querySelector('.show-glints');
      this.index=0;this.timer=null;this.started=0;this.remaining=null;this.running=false;this.ready=false;
      this.playButton.disabled=true;this.restartButton.disabled=true;if(this.glintsButton)this.glintsButton.disabled=true;
      if(spec.pending){this.status.textContent='В работе: движение ещё не подобрано';return;}
      this.playButton.addEventListener('click',()=>this.running?this.pause():this.play());
      this.restartButton.addEventListener('click',()=>this.restart());
      if(this.glintsButton)this.glintsButton.addEventListener('click',()=>this.seek(1));
      this.preload();
    }
    async preload(){
      const unique=[...new Set(this.spec.frames.map(f=>f.src))];
      try{
        await Promise.all(unique.map(src=>new Promise((resolve,reject)=>{
          const image=new Image();image.onload=resolve;image.onerror=()=>reject(new Error(src));image.src=src;
        })));
        this.ready=true;this.playButton.disabled=false;this.restartButton.disabled=false;
        if(this.glintsButton)this.glintsButton.disabled=false;
        this.show();if(this.spec.autoplay)this.play();
      }catch(error){this.status.textContent='Кадры ещё готовятся: '+error.message;}
    }
    show(){
      const pose=this.spec.frames[this.index];this.image.src=pose.src;
      this.status.textContent=pose.label+(this.running?' · воспроизведение':'');
      this.playButton.textContent=this.running?'Пауза':(this.spec.loop?'Играть':'Раскрыть');
    }
    tick(){
      if(!this.running)return;
      if(this.index===this.spec.frames.length-1&&!this.spec.loop){this.pause();return;}
      this.index=(this.index+1)%this.spec.frames.length;this.remaining=null;this.show();this.schedule();
    }
    schedule(){
      if(!this.running)return;
      const ms=this.remaining??this.spec.frames[this.index].ms;
      if(ms===null){this.pause();return;}
      this.started=performance.now();this.remaining=ms;
      this.timer=setTimeout(()=>this.tick(),ms);
    }
    play(){
      if(!this.ready||this.running)return;
      if(!this.spec.loop&&this.index===this.spec.frames.length-1){this.index=0;this.remaining=null;}
      this.running=true;this.show();this.schedule();
    }
    pause(){
      if(!this.running)return;
      clearTimeout(this.timer);this.timer=null;
      if(this.spec.frames[this.index].ms!==null)this.remaining=Math.max(0,(this.remaining??this.spec.frames[this.index].ms)-(performance.now()-this.started));
      this.running=false;this.show();
    }
    restart(){
      this.pause();this.index=0;this.remaining=null;this.show();this.play();
    }
    seek(index){
      this.pause();this.index=index;this.remaining=null;this.show();this.play();
    }
  }
  const clips={};for(const [id,spec] of Object.entries(specs))clips[id]=new Clip(id,spec);
  window.__hazardGallery={clips,specs};
})();
