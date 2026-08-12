import { useEffect, useRef } from "react";

const vertexShader = "attribute vec2 a;void main(){gl_Position=vec4(a,0.,1.);}";
const fragmentShader = [
  "precision highp float;",
  "uniform vec2 u_res;uniform float u_t;",
  "uniform vec3 u_c1;uniform vec3 u_c2;uniform vec3 u_c3;",
  "uniform float u_grain;uniform float u_glow;uniform vec2 u_glowpos;",
  "float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);}",
  "float n(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1.,0.)),f.x),mix(h(i+vec2(0.,1.)),h(i+vec2(1.,1.)),f.x),f.y);}",
  "float fbm(vec2 p){float v=0.;float a=.5;for(int i=0;i<5;i++){v+=a*n(p);p*=2.03;a*=.5;}return v;}",
  "void main(){vec2 uv=gl_FragCoord.xy/u_res.xy;vec2 p=uv*vec2(u_res.x/u_res.y,1.)*1.55;float t=u_t*.05;vec2 q=vec2(fbm(p+t),fbm(p+vec2(5.2,1.3)-t*.6));vec2 r=vec2(fbm(p+3.1*q+vec2(1.7,9.2)+t*.8),fbm(p+3.1*q+vec2(8.3,2.8)-t*.5));float f=fbm(p+2.9*r);vec3 col=mix(u_c1,u_c2,smoothstep(.12,.88,f));col=mix(col,u_c3,smoothstep(.38,1.05,length(q)));col+=u_glow*vec3(1.,.9,.78)*pow(clamp(1.-distance(uv,u_glowpos),0.,1.),3.2);col+=(h(gl_FragCoord.xy+fract(u_t)*7.)-.5)*u_grain;gl_FragColor=vec4(col,1.);}",
].join("\n");

function rgb(hex: string) {
  const value = hex.trim().replace("#", "");
  return [
    Number.parseInt(value.slice(0, 2), 16) / 255,
    Number.parseInt(value.slice(2, 4), 16) / 255,
    Number.parseInt(value.slice(4, 6), 16) / 255,
  ] as const;
}

type SkyProps = {
  colors: string;
  className?: string;
  glow?: number;
  glowPosition?: readonly [number, number];
  grain?: number;
  speed?: number;
  animate?: boolean;
};

export function Sky({
  colors,
  className,
  glow = 0.18,
  glowPosition = [0.72, 0.18],
  grain = 0.05,
  speed = 0.5,
  animate = true,
}: SkyProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const glowX = glowPosition[0];
  const glowY = glowPosition[1];

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const gl = canvas.getContext("webgl", {
      alpha: false,
      antialias: false,
      powerPreference: "low-power",
    });
    if (!gl) return;

    const compile = (type: number, source: string) => {
      const shader = gl.createShader(type);
      if (!shader) throw new Error("Unable to create Persome sky shader.");
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      return shader;
    };
    const program = gl.createProgram();
    if (!program) return;
    gl.attachShader(program, compile(gl.VERTEX_SHADER, vertexShader));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragmentShader));
    gl.linkProgram(program);
    gl.useProgram(program);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 3, -1, -1, 3]),
      gl.STATIC_DRAW,
    );
    const attribute = gl.getAttribLocation(program, "a");
    gl.enableVertexAttribArray(attribute);
    gl.vertexAttribPointer(attribute, 2, gl.FLOAT, false, 0, 0);

    const uniforms = {
      resolution: gl.getUniformLocation(program, "u_res"),
      time: gl.getUniformLocation(program, "u_t"),
      color1: gl.getUniformLocation(program, "u_c1"),
      color2: gl.getUniformLocation(program, "u_c2"),
      color3: gl.getUniformLocation(program, "u_c3"),
      grain: gl.getUniformLocation(program, "u_grain"),
      glow: gl.getUniformLocation(program, "u_glow"),
      glowPosition: gl.getUniformLocation(program, "u_glowpos"),
    };
    const palette = colors.split(",").map(rgb);
    const seed = Math.random() * 20;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let frame = 0;

    const render = (milliseconds: number) => {
      const bounds = canvas.getBoundingClientRect();
      const ratio = Math.min(window.devicePixelRatio || 1, bounds.width > 800 ? 1 : 1.5);
      const width = Math.max(2, Math.round(bounds.width * ratio));
      const height = Math.max(2, Math.round(bounds.height * ratio));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
      gl.viewport(0, 0, width, height);
      gl.uniform2f(uniforms.resolution, width, height);
      gl.uniform1f(uniforms.time, seed + milliseconds / 1000 * speed);
      gl.uniform3fv(uniforms.color1, palette[0]);
      gl.uniform3fv(uniforms.color2, palette[1]);
      gl.uniform3fv(uniforms.color3, palette[2]);
      gl.uniform1f(uniforms.grain, grain);
      gl.uniform1f(uniforms.glow, glow);
      gl.uniform2f(uniforms.glowPosition, glowX, glowY);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (animate && !reduceMotion) frame = requestAnimationFrame(render);
    };
    render(seed * 137);
    const resize = new ResizeObserver(() => render(performance.now()));
    resize.observe(canvas);
    return () => {
      cancelAnimationFrame(frame);
      resize.disconnect();
      gl.deleteBuffer(buffer);
      gl.deleteProgram(program);
    };
  }, [animate, colors, glow, glowX, glowY, grain, speed]);

  return <canvas aria-hidden="true" className={className} ref={canvasRef} />;
}
