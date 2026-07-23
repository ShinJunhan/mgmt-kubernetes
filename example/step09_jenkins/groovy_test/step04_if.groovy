// step04_if.groovy

def env = "prod"

// if 문을 이용해서 분기 할수 있다.
if( env == "prod"){
    println("개발 환경이군요!")
}else{
    println("다른 환경이군요!")
}

def num=10

if( num > 0){
    println("${num} 은 양수 입니다")
}else if( num == 0){
    println("${num} 은 zero 입니다")
}else{
    println("${num} 은 음수 입니다")
}

//삼항 연산자 (중요!)
def isDebug = true
def logLevel = isDebug ? "DEBUG" : "INFO"
println("Log level is set to ${logLevel}")