
/*
    (List/Array) 다루기
*/

def environments = ['dev', 'stg', 'prod']
// .each 함수를 이용해서 배열에 저장된 모든 item 불러와서 작업하기
environments.each { env ->
    println "Deploying to ${env} environment"
}

// 배열에 아이템 추가
environments.add("hello")
environments.add("bye")
environments << 'hi' // Groovy 스타일로 추가 
println(environments)
