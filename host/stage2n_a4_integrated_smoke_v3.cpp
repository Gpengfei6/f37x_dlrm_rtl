#include <xrt.h>
#include <experimental/xrt-next.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {
constexpr unsigned kDeviceIndex = 2;
constexpr const char* kTargetBdf = "0000:9b:00.1";
constexpr const char* kIpName =
    "dlrm_f37x_rtl_kernel_stage2n_a2:dlrm_a2_1";
constexpr unsigned kExpectedIpIndex = 0;
const unsigned char kExpectedUuidBytes[16] = {
    0xfb,0x8f,0x40,0x0f,0x70,0x64,0x45,0x83,
    0x9a,0x18,0x6c,0xf8,0x7a,0x46,0x5f,0xad
};

// Legacy MLP register window.
constexpr std::uint32_t A_CTL=0x000, A_VER=0x004, A_COUNT=0x008;
constexpr std::uint32_t A_LAYERS=0x010, A_INITBUF=0x014;
constexpr std::uint32_t A_DIDX=0x020, A_D0=0x024, A_D1=0x028, A_D2=0x02C;
constexpr std::uint32_t A_ABUF=0x040, A_ACHUNK=0x044, A_AMASK=0x048;
constexpr std::uint32_t A_AD0=0x050, A_AD1=0x054, A_AD2=0x058, A_AD3=0x05C;
constexpr std::uint32_t A_AD4=0x060, A_AD5=0x064, A_AD6=0x068, A_AD7=0x06C;
constexpr std::uint32_t A_WADDR=0x080, A_WDATA=0x084;
constexpr std::uint32_t A_BADDR=0x090, A_BDATA=0x094;
constexpr std::uint32_t A_RDATA=0x0A0, A_RIDX=0x0A4, A_RMETA=0x0A8;
constexpr std::uint32_t C_START=0x01, C_DESC=0x02, C_ACT=0x04;
constexpr std::uint32_t C_WEIGHT=0x08, C_BIAS=0x10, C_POP=0x20;
constexpr std::uint32_t C_CLEAR_DONE=0x80;
constexpr std::uint32_t S_BUSY=1u<<0, S_DONE=1u<<1, S_VALID=1u<<2;
constexpr std::uint32_t S_CORE_ERR=1u<<4, S_WRAP_ERR=1u<<5, S_PENDING=1u<<7;
constexpr std::uint32_t MLP_VERSION=0x00024701;

// Feature-interaction register window.
constexpr std::uint32_t I_CTL=0x100, I_VER=0x104, I_COUNT=0x108, I_SHIFT=0x10C;
constexpr std::uint32_t I_VIDX=0x110, I_VD0=0x114, I_VD1=0x118, I_VD2=0x11C, I_VD3=0x120;
constexpr std::uint32_t I_RDATA=0x124, I_RIDX=0x128, I_RMETA=0x12C, I_MASK=0x130;
constexpr std::uint32_t IC_LOAD=0x01, IC_START=0x02, IC_POP=0x04, IC_CLEAR_DONE=0x10;
constexpr std::uint32_t IS_BUSY=1u<<0, IS_DONE=1u<<1, IS_VALID=1u<<2, IS_LAST=1u<<3;
constexpr std::uint32_t IS_CORE_ERR=1u<<4, IS_WRAP_ERR=1u<<5, IS_LOAD_PENDING=1u<<6, IS_PENDING=1u<<7;
constexpr std::uint32_t IS_VECTOR_READY=1u<<8, IS_START_READY=1u<<9;
constexpr std::uint32_t INT_VERSION=0x00024E02;

const std::array<std::array<std::int16_t,8>,5> kVectors = {{
    {{ 1, 2, 3, 4, 5, 6, 7, 8}},
    {{ 1, 0,-1, 0, 1, 0,-1, 0}},
    {{ 2, 2, 2, 2, 2, 2, 2, 2}},
    {{-1,-2,-3,-4,-5,-6,-7,-8}},
    {{10, 9, 8, 7, 6, 5, 4, 3}}
}};
const std::array<std::int32_t,18> kExpected = {{
    1,2,3,4,5,6,7,8,-4,72,0,-204,4,-72,192,4,104,-192
}};

std::string hex32(std::uint32_t v) {
    std::ostringstream s; s << "0x" << std::hex << std::setw(8)
                            << std::setfill('0') << v; return s.str();
}
std::string uuid_string(const xuid_t u) {
    static const char* d="0123456789abcdef"; std::string s; s.reserve(36);
    for (int i=0;i<16;++i) { if(i==4||i==6||i==8||i==10) s.push_back('-');
        s.push_back(d[(u[i]>>4)&0xf]); s.push_back(d[u[i]&0xf]); }
    return s;
}

struct Desc { std::uint32_t w0,w1,w2; };
Desc pack_desc(std::uint32_t in, std::uint32_t out, std::uint32_t wb,
               std::uint32_t bb, std::uint32_t shift, bool relu) {
    __uint128_t v=0; v|=(__uint128_t)(in&0x7ffu);
    v|=(__uint128_t)(out&0x7ffu)<<11; v|=(__uint128_t)wb<<22;
    v|=(__uint128_t)bb<<54; v|=(__uint128_t)(shift&0x3fu)<<86;
    v|=(__uint128_t)(relu?1u:0u)<<92;
    return {static_cast<std::uint32_t>(v),static_cast<std::uint32_t>(v>>32),static_cast<std::uint32_t>(v>>64)};
}
std::uint32_t pack_pair(std::int16_t lo,std::int16_t hi) {
    return static_cast<std::uint32_t>(static_cast<std::uint16_t>(lo)) |
           (static_cast<std::uint32_t>(static_cast<std::uint16_t>(hi))<<16);
}

class Hal {
public:
    Hal() {
        std::memcpy(uuid_,kExpectedUuidBytes,sizeof(uuid_));
        h_=xclOpen(kDeviceIndex,nullptr,XCL_QUIET);
        if(!h_) throw std::runtime_error("xclOpen(index 2) failed");
        const int idx=xclIPName2Index(h_,kIpName);
        if(idx<0) throw std::runtime_error(std::string("xclIPName2Index failed for ")+kIpName+": "+std::to_string(idx));
        ip_=static_cast<unsigned>(idx);
        std::cout<<"HAL_DEVICE_INDEX="<<kDeviceIndex<<"\nHAL_TARGET_BDF="<<kTargetBdf
                 <<"\nHAL_XCLBIN_UUID="<<uuid_string(uuid_)<<"\nHAL_IP_NAME="<<kIpName
                 <<"\nHAL_IP_INDEX="<<ip_<<"\n";
        if(ip_!=kExpectedIpIndex) throw std::runtime_error("unexpected IP index");
        const int rc=xclOpenContext(h_,uuid_,ip_,false);
        if(rc) throw std::runtime_error("xclOpenContext(exclusive) failed: "+std::to_string(rc));
        opened_=true; std::cout<<"HAL_EXCLUSIVE_CONTEXT_OPEN=1\n";
    }
    ~Hal(){ if(opened_) xclCloseContext(h_,uuid_,ip_); if(h_) xclClose(h_); }
    Hal(const Hal&)=delete; Hal& operator=(const Hal&)=delete;
    void wr(std::uint32_t a,std::uint32_t v){ const int rc=xclRegWrite(h_,ip_,a,v);
        if(rc) throw std::runtime_error("xclRegWrite "+hex32(a)+" rc="+std::to_string(rc)); }
    std::uint32_t rd(std::uint32_t a)
    {
        std::uint32_t v = 0;
        const int rc = xclRegRead(h_, ip_, a, &v);
        if (rc) {
            throw std::runtime_error(
                "xclRegRead " + hex32(a) +
                " rc=" + std::to_string(rc));
        }
        return v;
    }
private:
    xclDeviceHandle h_=nullptr; xuid_t uuid_={}; unsigned ip_=0; bool opened_=false;
};

void mlp_error(std::uint32_t s,const char* c){
    if(s&(S_CORE_ERR|S_WRAP_ERR)) throw std::runtime_error(std::string(c)+" MLP status="+hex32(s));
}
void int_error(std::uint32_t s,const char* c){
    if(s&(IS_CORE_ERR|IS_WRAP_ERR)) throw std::runtime_error(std::string(c)+" interaction status="+hex32(s));
}
template<class P> std::uint32_t poll_mlp(Hal& h,P p,const char* d,int ms){
    const auto end=std::chrono::steady_clock::now()+std::chrono::milliseconds(ms); std::uint32_t s=0;
    while(std::chrono::steady_clock::now()<end){ s=h.rd(A_CTL); mlp_error(s,d); if(p(s)) return s;
        std::this_thread::sleep_for(std::chrono::microseconds(50)); }
    throw std::runtime_error(std::string("timeout ")+d+" status="+hex32(s));
}
template<class P> std::uint32_t poll_int(Hal& h,P p,const char* d,int ms){
    const auto end=std::chrono::steady_clock::now()+std::chrono::milliseconds(ms); std::uint32_t s=0;
    while(std::chrono::steady_clock::now()<end){ s=h.rd(I_CTL); int_error(s,d); if(p(s)) return s;
        std::this_thread::sleep_for(std::chrono::microseconds(50)); }
    throw std::runtime_error(std::string("timeout ")+d+" status="+hex32(s));
}
void wait_mlp_cmd(Hal& h,const char* d){ poll_mlp(h,[](std::uint32_t s){return !(s&S_PENDING);},d,2000); }
void wait_int_cmd(Hal& h,const char* d){ poll_int(h,[](std::uint32_t s){return !(s&(IS_PENDING|IS_LOAD_PENDING));},d,2000); }

void write_desc(Hal& h,std::uint32_t i,const Desc& d){ h.wr(A_DIDX,i);h.wr(A_D0,d.w0);h.wr(A_D1,d.w1);h.wr(A_D2,d.w2);h.wr(A_CTL,C_DESC);wait_mlp_cmd(h,"descriptor commit"); }
void write_weight(Hal& h,std::uint32_t a,std::int8_t v){ h.wr(A_WADDR,a);h.wr(A_WDATA,static_cast<std::uint8_t>(v));h.wr(A_CTL,C_WEIGHT);wait_mlp_cmd(h,"weight commit"); }
void write_bias(Hal& h,std::uint32_t a,std::int32_t v){ h.wr(A_BADDR,a);h.wr(A_BDATA,static_cast<std::uint32_t>(v)&0x00ffffffu);h.wr(A_CTL,C_BIAS);wait_mlp_cmd(h,"bias commit"); }
void write_act(Hal& h,std::int16_t v){ h.wr(A_ABUF,0);h.wr(A_ACHUNK,0);h.wr(A_AMASK,1);h.wr(A_AD0,static_cast<std::uint16_t>(v));
    h.wr(A_AD1,0);h.wr(A_AD2,0);h.wr(A_AD3,0);h.wr(A_AD4,0);h.wr(A_AD5,0);h.wr(A_AD6,0);h.wr(A_AD7,0);h.wr(A_CTL,C_ACT);wait_mlp_cmd(h,"activation commit"); }

void run_mlp(Hal& h){
    const auto ver=h.rd(A_VER); auto st=h.rd(A_CTL);
    std::cout<<"MLP_VERSION="<<hex32(ver)<<"\nMLP_INITIAL_STATUS="<<hex32(st)<<"\n";
    if (ver != MLP_VERSION) {
        throw std::runtime_error("MLP version mismatch");
    }
    mlp_error(st, "initial");
    if(st&(S_BUSY|S_VALID|S_PENDING)) throw std::runtime_error("MLP not idle: "+hex32(st));
    if(st&S_DONE){h.wr(A_CTL,C_CLEAR_DONE);poll_mlp(h,[](std::uint32_t s){return !(s&S_DONE);},"clear MLP done",1000);}
    write_desc(h,0,pack_desc(1,1,0,0,0,false)); write_desc(h,1,pack_desc(1,1,1,1,0,false));
    write_weight(h,0,2);write_weight(h,1,3);write_bias(h,0,1);write_bias(h,1,-2);write_act(h,3);
    h.wr(A_LAYERS,2);h.wr(A_INITBUF,0);h.wr(A_CTL,C_START);wait_mlp_cmd(h,"MLP start");
    st=poll_mlp(h,[](std::uint32_t s){return s&S_VALID;},"MLP result",5000);
    const std::int32_t result=static_cast<std::int32_t>(h.rd(A_RDATA));
    const auto idx=h.rd(A_RIDX)&0x3ffu; const auto meta=h.rd(A_RMETA); const auto tag=(meta>>8)&0xffu;
    std::cout<<"MLP_RESULT_STATUS="<<hex32(st)<<"\nMLP_RESULT="<<result<<"\nMLP_RESULT_INDEX="<<idx
             <<"\nMLP_RESULT_META="<<hex32(meta)<<"\nMLP_RESULT_LAYER_TAG="<<tag<<"\n";
    if(result!=19||idx!=0||(meta&3u)!=3u||tag!=1) throw std::runtime_error("MLP result contract mismatch");
    h.wr(A_CTL,C_POP);poll_mlp(h,[](std::uint32_t s){return s&S_DONE;},"MLP done",5000);
    if(h.rd(A_COUNT)!=1) throw std::runtime_error("MLP result count mismatch");
    h.wr(A_CTL,C_CLEAR_DONE);poll_mlp(h,[](std::uint32_t s){return !(s&(S_BUSY|S_DONE|S_VALID|S_PENDING));},"MLP idle",1000);
    std::cout<<"MLP_SMOKE_PASS=1\n";
}

void load_vec(Hal& h,std::uint32_t i,const std::array<std::int16_t,8>& v){
    h.wr(I_VIDX,i);h.wr(I_VD0,pack_pair(v[0],v[1]));h.wr(I_VD1,pack_pair(v[2],v[3]));
    h.wr(I_VD2,pack_pair(v[4],v[5]));h.wr(I_VD3,pack_pair(v[6],v[7]));h.wr(I_CTL,IC_LOAD);wait_int_cmd(h,"vector load");
}
void wait_idx(Hal& h,std::uint32_t wanted){
    const auto end=std::chrono::steady_clock::now()+std::chrono::milliseconds(5000); std::uint32_t s=0,idx=0xffffffffu;
    while(std::chrono::steady_clock::now()<end){s=h.rd(I_CTL);int_error(s,"interaction result");if(s&IS_VALID){idx=h.rd(I_RIDX)&0x1fu;if(idx==wanted)return;}
        std::this_thread::sleep_for(std::chrono::microseconds(50));}
    throw std::runtime_error("timeout result index "+std::to_string(wanted)+" last="+std::to_string(idx)+" status="+hex32(s));
}
void run_interaction(Hal& h){
    const auto ver=h.rd(I_VER);
    auto st=h.rd(I_CTL);
    std::cout<<"INT_VERSION="<<hex32(ver)
             <<"\nINT_INITIAL_STATUS="<<hex32(st)<<"\n";

    if (ver != INT_VERSION) {
        throw std::runtime_error("interaction version mismatch");
    }

    int_error(st, "initial");

    if(st&(IS_BUSY|IS_VALID|IS_LOAD_PENDING|IS_PENDING)) {
        throw std::runtime_error(
            "interaction not quiescent before recovery: "+hex32(st));
    }

    const bool stale_done=(st&IS_DONE)!=0;

    // The interaction core keeps its raw done level asserted in STATE_IDLE
    // until a new vector load or start is accepted. Therefore CLEAR_DONE
    // cannot remain cleared while raw done is still high. Load vector 0 first
    // to deassert the raw core-done level, then clear the wrapper latch.
    load_vec(h,0,kVectors[0]);

    if(stale_done){
        h.wr(I_CTL,IC_CLEAR_DONE);
        poll_int(
            h,
            [](std::uint32_t s){
                return !(s&(IS_DONE|IS_BUSY|IS_VALID|
                            IS_LOAD_PENDING|IS_PENDING));
            },
            "recover stale interaction done",
            1000);
        std::cout<<"INT_STALE_DONE_RECOVERED=1\n";
    }else{
        std::cout<<"INT_STALE_DONE_RECOVERED=0\n";
    }

    for(std::size_t i=1;i<kVectors.size();++i){
        load_vec(h,static_cast<std::uint32_t>(i),kVectors[i]);
    }

    const auto mask=h.rd(I_MASK)&0x1fu;
    std::cout<<"INT_LOADED_MASK="<<hex32(mask)<<"\n";
    if(mask!=0x1fu) {
        throw std::runtime_error("loaded mask mismatch");
    }

    h.wr(I_SHIFT,0);
    h.wr(I_CTL,IC_START);
    wait_int_cmd(h,"interaction start");

    for(std::size_t n=0;n<kExpected.size();++n){
        wait_idx(h,static_cast<std::uint32_t>(n));
        st=h.rd(I_CTL);

        const std::int32_t val=
            static_cast<std::int32_t>(h.rd(I_RDATA));
        const auto idx=h.rd(I_RIDX)&0x1fu;
        const auto meta=h.rd(I_RMETA);
        const bool last=(n+1==kExpected.size());

        std::cout<<"INT_OUTPUT["<<n<<"]="<<val
                 <<" INDEX="<<idx
                 <<" META="<<hex32(meta)<<"\n";

        if(val!=kExpected[n]||
           idx!=n||
           ((meta>>8)&0x1fu)!=n||
           !(meta&1u)||
           (((meta&2u)!=0)!=last)||
           (((st&IS_LAST)!=0)!=last)){
            throw std::runtime_error(
                "interaction output contract mismatch at "+
                std::to_string(n));
        }

        h.wr(I_CTL,IC_POP);
    }

    const auto terminal_status=poll_int(
        h,
        [](std::uint32_t s){
            return (s&IS_DONE) &&
                   !(s&(IS_BUSY|IS_VALID|
                        IS_LOAD_PENDING|IS_PENDING));
        },
        "interaction terminal done",
        5000);

    const auto count=h.rd(I_COUNT);
    if(count!=18) {
        throw std::runtime_error(
            "interaction count mismatch: "+std::to_string(count));
    }

    if((terminal_status&(IS_VECTOR_READY|IS_START_READY)) !=
       (IS_VECTOR_READY|IS_START_READY)){
        throw std::runtime_error(
            "interaction terminal ready bits mismatch: "+
            hex32(terminal_status));
    }

    std::cout<<"INT_RESULT_COUNT="<<count
             <<"\nINT_TERMINAL_STATUS="<<hex32(terminal_status)
             <<"\nINTERACTION_TERMINAL_DONE_ACCEPTED=1"
             <<"\nINTERACTION_SMOKE_PASS=1\n";
}
} // namespace

int main(){
    try{
        std::cout<<"Stage 2N-A4 integrated F37X board smoke\nAccess=xclOpenContext+xclRegRead+xclRegWrite\n";
        Hal h;run_mlp(h);run_interaction(h);
        std::cout<<"STAGE2N_A4_INTEGRATED_SMOKE_V3_PASS mlp_result=19 interaction_outputs=18\n";
        return EXIT_SUCCESS;
    }catch(const std::exception& e){std::cerr<<"STAGE2N_A4_INTEGRATED_SMOKE_FAIL: "<<e.what()<<"\n";return EXIT_FAILURE;}
}
