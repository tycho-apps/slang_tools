//--------------------------------------------------------------------------------------
// File: ContentStreaming.fx
//
// The effect file for the ContentStreaming sample.  
// 
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
float g_TimeShift;						// global timer
float4x4 g_mWorld;                  // World matrix for object
float4x4 g_mWorldViewProjection;    // World * View * Projection matrix
float4 g_vEyePt;
float4 g_vAmbient = float4(0.318,0.320,0.424,0);
float4 g_vLightColor[2] = { float4(1.0,.991,.869,1), float4(0,.238,.475,1) };
float3 g_vLightDir[2] = { float3(0.426189, 0.303274, -0.852284), float3(0.418468,-0.850755,0.317962) };
float4 g_vSpecularColor = float4(0.525,0.341,0.175,0);
float g_d3d10alpharef = 90.0/255.0;

//-----------------------------------------------------------------------------------------
// Textures and Samplers
//-----------------------------------------------------------------------------------------
texture2D g_txDiffuse;
texture2D g_txNormal;
texture2D g_txShadow;
texture2D g_txNoise;

sampler2D MeshDiffuseSampler = sampler_state
{
    Texture = (g_txDiffuse);
#ifndef D3D10
    MinFilter = Linear;
    MagFilter = Linear;
#endif
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D MeshNormalSampler = sampler_state
{
    Texture = (g_txNormal);
#ifndef D3D10
    MinFilter = Linear;
    MagFilter = Linear;
#endif
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D MeshShadowSampler = sampler_state
{
    Texture = (g_txShadow);
#ifndef D3D10
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
#endif
    AddressU = CLAMP;
    AddressV = CLAMP;
};

sampler2D MeshNoiseSampler = sampler_state
{
    Texture = (g_txNoise);
#ifndef D3D10
    MinFilter = Linear;
    MagFilter = Linear;
#endif
    AddressU = WRAP;
    AddressV = WRAP;
};

#ifdef D3D10
BlendState AdditiveBlending
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = TRUE;
    SrcBlend = SRC_ALPHA;
    DestBlend = INV_SRC_ALPHA;
    BlendOp = ADD;
    SrcBlendAlpha = ZERO;
    DestBlendAlpha = ZERO;
    BlendOpAlpha = ADD;
    RenderTargetWriteMask[0] = 0x0F;
};

BlendState NoBlending
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = FALSE;
    SrcBlend = SRC_ALPHA;
    DestBlend = ONE;
    BlendOp = ADD;
    SrcBlendAlpha = ZERO;
    DestBlendAlpha = ZERO;
    BlendOpAlpha = ADD;
    RenderTargetWriteMask[0] = 0x0F;
};

RasterizerState CullFront
{
    CullMode = FRONT;
};

RasterizerState CullBack
{
    CullMode = BACK;
};

#endif

//--------------------------------------------------------------------------------------
// shader input/output structure
//--------------------------------------------------------------------------------------
struct VS_OBJECTINPUT
{
    float4 Position   : POSITION;   // vertex position 
    float3 Normal     : NORMAL;		// this normal comes in per-vertex
    float2 TextureUV  : TEXCOORD0;  // vertex texture coords 
};

struct VS_OBJECTOUTPUT
{
    float4 Position   : POSITION;   // vertex position 
    float4 Diffuse    : COLOR0;     // vertex diffuse color (note that COLOR0 is clamped from 0..1)
    float2 TextureUV  : TEXCOORD0;  // vertex texture coords 
    float1 TextureUV2 : TEXCOORD1;  // texture coords for lines
};

struct VS_LEVELINPUT
{
    float4 Position   : POSITION;   // vertex position 
    float3 Normal     : NORMAL;		// this normal comes in per-vertex
    float2 TextureUV  : TEXCOORD0;  // vertex texture coords 
    float2 ShadowUV   : TEXCOORD1;  // shadow map texture coords
    float3 Tangent	  : TANGENT;	// tangent
};

struct VS_LEVELOUTPUT
{
    float4 Position   : POSITION;   // vertex position 
    float3 Normal     : TEXCOORD0;	// this normal comes in per-vertex
    float2 TextureUV  : TEXCOORD1;  // vertex texture coords 
    float2 ShadowUV   : TEXCOORD3;  // shadow map texture coords
    float3 Tangent	  : TEXCOORD4;	// tangent
    float3 ViewDir	  : TEXCOORD5;  // view direction
    float  Attenuate  : TEXCOORD6;	// atmo attenuation
};


//--------------------------------------------------------------------------------------
// This shader computes standard transform and lighting
//--------------------------------------------------------------------------------------
VS_OBJECTOUTPUT RenderObjectVS( VS_OBJECTINPUT input )
{
    VS_OBJECTOUTPUT Output;
    float3 vNormalWorldSpace;
    
    // Transform the position from object space to homogeneous projection space
    Output.Position = mul( input.Position, g_mWorldViewProjection);
    
    // Transform the normal from object space to world space    
    vNormalWorldSpace = normalize(mul(input.Normal, (float3x3)g_mWorld)); // normal (world space)

    // Calc diffuse color    
    if( input.Normal.x == 0 && input.Normal.y == 0 && input.Normal.z == 0 )
        vNormalWorldSpace = g_vLightDir[0];
        
    float4 lightColor = float4(0,0,0,0);
    for( int i=0; i<2; i++ )
    {
        lightColor += g_vLightColor[i] * max( 0,dot(vNormalWorldSpace, g_vLightDir[i]) ); 
    }
    lightColor += g_vAmbient;
    
    Output.Diffuse = lightColor;   
    Output.Diffuse.a = 1.0f; 
    
    // Just copy the texture coordinate through
    Output.TextureUV = input.TextureUV;
    
    // Move the noise texture across the surface
    float3 worldPos = mul( input.Position, g_mWorld );
    Output.TextureUV2 = 2.0*(worldPos.y - g_TimeShift); 
    
    return Output;    
}

//--------------------------------------------------------------------------------------
// This shader outputs the pixel's color by modulating the texture's
// color with diffuse material color
//--------------------------------------------------------------------------------------
float4 RenderObjectPS( VS_OBJECTOUTPUT In ) : COLOR0
{ 
    float4 diffuse = tex2D( MeshDiffuseSampler, In.TextureUV);
    float4 noise2D = tex2D( MeshNoiseSampler, In.TextureUV * 2);
    float4 noise1D = tex2D( MeshNoiseSampler, float2(0,In.TextureUV2) );
    
    diffuse.a = 0.6f + noise2D.r * noise1D.a;
    diffuse.rgb *= In.Diffuse;
    diffuse.b += 0.2;
    
    return diffuse;
}

//--------------------------------------------------------------------------------------
// This shader computes standard transform and a normal/tangent frame
//--------------------------------------------------------------------------------------
VS_LEVELOUTPUT RenderLevelVS( VS_LEVELINPUT input )
{
    VS_LEVELOUTPUT Output;
    
    // Transform the position from object space to homogeneous projection space
    Output.Position = mul( input.Position, g_mWorldViewProjection);
    
    // Transform the normal from object space to world space    
    Output.Normal = normalize(mul(input.Normal, (float3x3)g_mWorld)); // normal (world space)

    // Calc diffuse color    
    Output.Tangent = normalize(mul(input.Tangent, (float3x3)g_mWorld)); // tangent (world space)
    
    // Just copy the texture coordinate through
    Output.TextureUV = input.TextureUV; 
    Output.ShadowUV = input.ShadowUV;
    
    // view dir
    float4 worldPos = mul( input.Position, g_mWorld );
    Output.ViewDir = g_vEyePt.xyz - worldPos.xyz;
    
    // Fake atmo attenuation
    float attenuate = dot( Output.ViewDir, Output.ViewDir ) / 3000.0;
    Output.Attenuate = attenuate;
    
    return Output;    
}

//--------------------------------------------------------------------------------------
// This shader computes normal mapped lighting and alpha transparency
//--------------------------------------------------------------------------------------
float4 RenderLevelPS( VS_LEVELOUTPUT Input, uniform float lightFlip ) : COLOR0
{ 
    // Lookup mesh texture and modulate it with diffuse
    float4 diffuse = tex2D( MeshDiffuseSampler, Input.TextureUV );
    float4 shadow = tex2D( MeshShadowSampler, Input.ShadowUV ).rrrr;
    float3 bump = tex2D( MeshNormalSampler, Input.TextureUV );
    bump *= 2.0;
    bump -= 1;
    
#ifdef D3D10
    if( diffuse.a < g_d3d10alpharef )
        discard;
#endif

    // move bump into world space
    float3 binorm = normalize( cross( Input.Normal, Input.Tangent ) );
    float3x3 tanMatrix = float3x3( binorm, Input.Tangent, Input.Normal );
    bump = mul( bump, tanMatrix );

    float4 lightColor = float4(0,0,0,0);
    float specAmt = 0;
    
    float3 NormViewDir = normalize( Input.ViewDir );
    for( int i=0; i<2; i++ )
    {
        lightColor += g_vLightColor[i] * max( 0,dot(bump, g_vLightDir[i]*lightFlip) ); 
        
        float3 halfAngle = normalize( NormViewDir + g_vLightDir[i]*lightFlip );
        specAmt += saturate( pow( dot( halfAngle, bump ), 32 ) );
    }
    
    lightColor = lightColor * shadow + g_vAmbient;
    float4 attenColor = float4(0.15, 0.2, 0.3, 0);
    float4 color1 = (1.0 - Input.Attenuate*0.15)*(lightColor*diffuse + specAmt*g_vSpecularColor*shadow);
    color1.a = diffuse.a;
    return color1 + Input.Attenuate*attenColor;
}

//--------------------------------------------------------------------------------------
// This shader outputs the pixel's color by modulating the texture's
// color with diffuse material color
//--------------------------------------------------------------------------------------
float4 RenderSkyPS( VS_LEVELOUTPUT In ) : COLOR0
{ 
    float4 diffuse = tex2D( MeshDiffuseSampler, In.TextureUV);  
    float4 blueColor = g_vLightColor[1] * max( 0,dot(In.Normal, g_vLightDir[1]) );
    return diffuse * ( blueColor + 1 );
}

//--------------------------------------------------------------------------------------
// Renders scene for Direct3D 9
//--------------------------------------------------------------------------------------
technique RenderObject
{
    pass P0
    {   
        VertexShader = compile vs_2_0 RenderObjectVS();
        PixelShader  = compile ps_2_0 RenderObjectPS();
        
        AlphaBlendEnable = true;
        SrcBlend = SrcAlpha;
        DestBlend = InvSrcAlpha;
        BlendOp = ADD;
        
        AlphaTestEnable = false;
        CullMode = CCW;
    }
}

technique RenderLevel_BACK
{
    pass P0
    {   
        VertexShader = compile vs_2_0 RenderLevelVS();
        PixelShader  = compile ps_2_0 RenderLevelPS(-1.0f);
        
        AlphaBlendEnable = false;
        AlphaTestEnable = true;
        AlphaFunc = GREATER;
        AlphaRef = 90;
        
        CullMode = CW;
        
    }
}

technique RenderLevel_FRONT
{
    pass P0
    {   
        VertexShader = compile vs_2_0 RenderLevelVS();
        PixelShader  = compile ps_2_0 RenderLevelPS(1.0f);
        
        AlphaBlendEnable = false;
        AlphaTestEnable = true;
        AlphaFunc = GREATER;
        AlphaRef = 90;
        
        CullMode = CCW;
        
    }
}

technique RenderSky
{
    pass P0
    {   
        VertexShader = compile vs_2_0 RenderLevelVS();
        PixelShader  = compile ps_2_0 RenderSkyPS();
        
        AlphaBlendEnable = false;
        AlphaTestEnable = false;
        
        CullMode = CCW;
        
    }
}

//--------------------------------------------------------------------------------------
// RendersScene Multi Index for Direct3D 10
//--------------------------------------------------------------------------------------
#ifdef D3D10
technique10 RenderObject
{
    pass P0
    {       
        SetVertexShader( CompileShader( vs_4_0, RenderObjectVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, RenderObjectPS() ) );
        
        SetBlendState( AdditiveBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( CullBack );
    }
}

technique10 RenderLevel_BACK
{
    pass P0
    {   
        SetVertexShader( CompileShader( vs_4_0, RenderLevelVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, RenderLevelPS(-1.0) ) );
        
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( CullFront );
    }
}

technique10 RenderLevel_FRONT
{
    pass P0
    {   
        SetVertexShader( CompileShader( vs_4_0, RenderLevelVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, RenderLevelPS(1.0) ) );
        
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( CullBack );
    }
}

technique10 RenderSky
{
    pass P0
    {   
        SetVertexShader( CompileShader( vs_4_0, RenderLevelVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, RenderSkyPS() ) );
              
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );  
        SetRasterizerState( CullBack );
    }
}

#endif
