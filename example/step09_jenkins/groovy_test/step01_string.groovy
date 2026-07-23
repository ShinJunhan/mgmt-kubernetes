
/*
    groovy 에서 여러줄 주석입니다.

    문자열(String)을 다뤄 보기
*/

// 한줄 주석입니다.

// 변수 선언하고 문자열 대입
def appName = "fortune"
def tag = "v1"
println("Deploying ${appName} with tag ${tag}")

// 여러줄의 문자열 만들기
def query = """
    SELECT *
    FROM members
"""
println(query)

// 문자열 자르기 (split)
def branchName = "feature/login-page"
// parts 는 배열이다 
def parts = branchName.split('/')
// 배열의 0 번방, 1번방을 참조해서 출력하기 
println "Branch type: ${parts[0]}, Name: ${parts[1]}" //괄호 없이 바로 출력할수도 있다.


// 문자열 치환
def url = "http://172.16.8.42/admin"
def secureUrl = url.replace("http://", "https://")
println(secureUrl)