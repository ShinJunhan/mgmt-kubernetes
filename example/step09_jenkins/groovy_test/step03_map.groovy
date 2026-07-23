// step03_map.groovy 파일

// map 데이터 만들어서 참조하기
def mem = [num:1, name:"kim", addr:"seoul"]
println("번호:${mem.num} 이름:${mem.name} 주소:${mem.addr}")

// map 에 저장된 모든 item 을 순회해서 활용하기 
def imageTags = [fortune:"v1", greet:"v2"]
imageTags.each { key, value ->
    println "App:${key} Tag:${value}"
}